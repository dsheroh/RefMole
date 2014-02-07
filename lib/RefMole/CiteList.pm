package RefMole::CiteList;

use strict;
use warnings;
use 5.010;

use RefMole::Config 'cfg';

use POSIX qw( ceil );

### BEGIN ORMS LIFE-SUPPORT ###
use lib cfg->{sbcat_path} . '/lib/extension';
use lib cfg->{sbcat_path} . '/lib/default';
use luurCfg;
use Orms;
use Cwd;
my $cfg;
BEGIN {
  $ENV{HOSTNAME} //= `hostname --fqdn`;
  my $original_path = getcwd;
  chdir cfg->{sbcat_path};
  $cfg = luurCfg->new;
  chdir $original_path;
}
### END ORMS LIFE-SUPPORT ###

use CSL;
use Encode;
use FindBin '$RealBin';
use LWP::UserAgent;
use Template;
use XML::Simple;

my %internal_style = map { $_ => 1 } qw( std );

sub apply_csl {
  my ($publications) = @_;

  my $i = 0;
  for (@{$publications->{records}}) {
    $_->{_oid_save} = $_->{recordid};
    $_->{recordid} = $i++;
  }

  my ($style, $locale) = split '--', $publications->{style}, 2;
  $publications->{locale} = $locale if $locale;

  my $csl = CSL->new(cfg => cfg);
  my $citations = $csl->process($style, $publications);

  my %cite_map = map { $_->{id} => $_->{citation} } @$citations;

  $i = 0;
  for (@{$publications->{records}}) {
    my $citation = $cite_map{$_->{recordid}};
    $_->{recordid} = $_->{_oid_save};

    $citation = decode('iso-8859-1', $citation) unless utf8::decode($citation);
    $_->{citation} = $citation;
  }

  # Return nothing because $publications was modified in-place
  return;
}

sub format_citations {
  my ($publications) = @_;

  my $style = $publications->{style};
  return apply_csl(@_) unless $internal_style{$style};

  my $template_path = "$RealBin/../views/cite_style/";
  my $formatter = Template->new(
    INCLUDE_PATH => $template_path,
    DEFAULT      => 'std.tt',
    START_TAG    => '<%',
    END_TAG      => '%>',
    TRIM         => 1,
  );
  my $template = $style . '.tt';
  for my $rec (@{$publications->{records}}) {
    my $citation;
    $rec->{author_limit} = cfg->{sru}{author_limit};
    $rec->{extra_author_text} = cfg->{sru}{extra_author_text};
    $formatter->process($template, $rec, \$citation) or die $formatter->error;
    $rec->{citation} = $citation;
  }

  # Return nothing because $publications was modified in-place
  return;
}

sub get_detail {
  my ($param) = @_;

  return unless $param->{id};
  $param->{limit} = 1;

  my $query_url = cfg->{sru}{url}
    . "&query=id%20exact%20%22$param->{id}%22";
  my $result = _get_records($query_url, $param);

  $result->{records}[0]{id} = $param->{id};
  $result->{style} = $param->{style} || cfg->{csl_engine}{default_style};

  return $result;
}

sub get_publications {
  my ($param) = @_;

  my $conditions;

  if ($param->{author}) {
    $param->{author} =~ s/\s//g;
    my @authors = split ',', $param->{author};

    my $auth_str = join ' or ', map { qq{author exact "$_"} } @authors;
    my $edit_str = join ' or ', map { qq{editor exact "$_"} } @authors;

    $conditions = "($auth_str or (($edit_str) "
          . "and (documentType exact bookEditor "
          . "or documentType exact conferenceEditor "
          . "or documentType exact journalEditor)))";
  } elsif ($param->{supervisor}) {
    $param->{supervisor} =~ s/\s//g;
    $param->{supervisor} =~ s/,/ /g;
    $conditions = '(supervisor any "' . $param->{supervisor} . '")';
  } elsif ($param->{favlist}) {
    # Loads of redundancy here because of favlist not being a CQL query term;
    # TODO: Refactor to DRY
    my $query_url = cfg->{sru}{url} . '&favList=' . $param->{favlist}
      . '&query=id exact 0';
    my $result = _get_records($query_url, $param);
    $result->{style} = lc ($param->{style} || cfg->{csl_engine}{default_style});

    return $result;
  } else {
    if ($param->{record}) {
      $param->{id} = $param->{record};
      $param->{id} =~ s/[^0-9,]//g
    }
    for (qw( department project researchgroup issn id )) {
      if ($param->{$_}) {
        $conditions = _multi_organization_criteria($param, $_);
        last;
      }
    }
  }

  return {} unless $conditions;

  if (my $datespec = $param->{publyear}) {
    if ($datespec =~ /(\d*)-(\d*)/) {
      $conditions .= " AND publishingYear >= $1" if $1;
      $conditions .= " AND publishingYear <= $2" if $2;
    } else {
      $conditions .= " AND publishingYear = $datespec";
    }
  }

  $conditions .= qq( AND dateApproved >= "$param->{dateappr}")
    if $param->{dateappr};

  if ($param->{doctype}) {
    if (ref($param->{doctype})) {
      $conditions .=
        ' AND (documentType ANY "' . join(' ', @{$param->{doctype}}) . '")';
    } else {
      $conditions .= qq( AND documentType="$param->{doctype}");
    }
  }

  $conditions .= qq" NOT documentType exact StudentPaper"
    unless $param->{show_papers} || $param->{id} || $param->{doctype};

  $conditions .= " AND qualityControlled exact $param->{qc}"
    if defined $param->{qc};

  $conditions .= " AND popularScience exact $param->{popsci}"
    if defined $param->{popsci};

  my $sort_dir = 0;
  if (lc ($param->{sortdir} || '') eq 'asc') {
    $sort_dir = 1;
  }

  my $query_url = cfg->{sru}{url} . "&query=$conditions"
    . "&sortKeys=publishingYear,,$sort_dir dateApproved,,$sort_dir";

  my $result = _get_records($query_url, $param);

  if ($param->{author}) {
    $result->{norm_author} = _switch_author($param->{author});
    $result->{list_author} = $param->{author};
  }

  $result->{style} = lc ($param->{style} || cfg->{csl_engine}{default_style});

  $result->{list_dept} = $param->{dept} if defined $param->{dept};

  return $result;
}

sub _add_record_fields {
  my $rec = shift;
  my %result;

  my $mods = $rec->{mods};

  $result{recordid} = $mods->{recordInfo}{recordIdentifier};

  if (ref $mods->{genre}) {
    $result{type} = $mods->{genre}{content};
  } else {
    $result{type} = $mods->{genre};
  }

  push @{$result{title}}, $_->{title} for @{$mods->{titleInfo}};

  $result{publ_year} = $mods->{originInfo}{dateIssued}{content};
  $result{publisher} = $mods->{originInfo}{publisher};
  if (ref $mods->{language} eq 'ARRAY') {
    $result{language}  = $mods->{language}[0]{languageTerm}{content};
  } else {
    $result{language}  = $mods->{language}{languageTerm}{content};
  }

  $result{place} = $mods->{originInfo}{place}{placeTerm}{content}
    if $mods->{originInfo}{place}{placeTerm}{content};

  for my $note (@{$mods->{note}}) {
    if ($note->{type} eq 'publicationStatus') {
      $result{publstatus} = $note->{content};
    } elsif ($note->{type} eq 'reviewedWorks' && $note->{content}) {
      my $tmp = $note->{content};
      $tmp =~ s/au://;
      $tmp =~ s/ti//;
      $tmp =~ tr/\n//d;
      $result{reviewedwork} = $tmp;
    }
  }

  for (@{$mods->{abstract}}) {
    push @{$result{abstract}}, $_->{content} if $_->{content};
  }

  for my $entity (@{$mods->{name}}) {
    if ($entity->{type} eq 'conference') {
      $result{conference} = $entity->{namePart};
      next;
    }

    my $role = $entity->{role}[0]{roleTerm}{content};
    next unless $role;

    $role = 'author'
      if $role eq 'reviewer' || $role eq 'author: translated work';

    if (ref $entity->{namePart} eq 'ARRAY') {
      my $person;
      for my $name_part (@{$entity->{namePart}}) {
        eval {
          $name_part->{content} = decode('iso-8859-1', $name_part->{content})
            unless utf8::decode($name_part->{content});
        };

        $person->{given}  = $name_part->{content}
          if $name_part->{type} eq 'given';
        $person->{family} = $name_part->{content}
          if $name_part->{type} eq 'family';
      }
      $person->{full} = trim($person->{family} . ', ' . $person->{given});
      push @{$result{$role}}, $person;
      push @{$result{$role . 's'}}, $person->{full};
    } elsif ($role eq 'department') {
      push @{$result{affiliation}}, $entity->{namePart};
    } elsif ($role eq 'project') {
      push @{$result{project}}, $entity->{namePart};
    } elsif ($role eq 'research group') {
      push @{$result{researchgroup}}, $entity->{namePart};
    }
  }

  $result{author_count} = $mods->{authorCount} if $mods->{authorCount};

  for my $subj (@{$mods->{subject}}) {
    next unless ref $subj->{topic} eq 'ARRAY';

    push @{$result{subject}}, $_ for @{$subj->{topic}};
  }

  for my $related (@{$mods->{relatedItem}}) {
    my $entry;

    for (@{$related->{titleInfo}}) {
      $entry->{title} = $_->{title} if $_->{title};
    }

    if ($related->{location}{url}) {
      if (ref $related->{location}{url}) {
        if ($related->{type} eq 'constituent') {
          push @{$entry->{label}}, $related->{location}{url}{displayLabel};
        }
        if ($related->{location}{url}{content}) {
          push @{$entry->{url}}, $related->{location}{url}{content};
        }
      } else {
        if ($related->{type} eq 'constituent') {
          $entry->{label} = $related->{location}{url};
        } else {
          $entry->{url} = $related->{location}{url};
        }
      }
    }

    for (@{$related->{identifier}}) {
      if ($_->{type} eq 'other') {
        if ($_->{content} =~ /(\w+):(.*)/) {
          push @{$entry->{lc $1}}, $2;
        }
      } else {
        push @{$entry->{$_->{type}}}, $_->{content};
      }
    }

    for (@{$related->{part}{extent}}) {
      $entry->{pages} = $_->{content} if $_->{content};
      if ($_->{start}) {
        $entry->{prange} = $_->{start};
        $entry->{prange} .= ' - ' . $_->{end} if $_->{end} && !ref $_->{end};
      } else {
        $entry->{prange} = $_->{end} unless ref $_->{end};
      }
    }

    if ($related->{part}{detail}) {
      for my $part (@{$related->{part}{detail}}) {
        if ($part->{number}) {
          $entry->{volume} = $part->{number} if $part->{type} eq 'volume';
          $entry->{issue}  = $part->{number} if $part->{type} eq 'issue';
        }
      }
    }

    if ($related->{accessCondition}) {
      for my $cond (@{$related->{accessCondition}}) {
        if ($cond->{type} eq 'restrictionOnAccess' && $cond->{content} eq 'yes')
        {
          $entry->{restricted_access} = 1;
        }
      }
    }

    push @{$result{$related->{type}}}, $entry if $entry;
  }

  return \%result;
}

sub _extract_mods {
  my ($mods_xml) = @_;

  my $parser = XML::Simple->new;

  my $xml = $parser->XMLin( $mods_xml, forcearray => [ qw(
    record subject relatedItem detail note abstract name role titleInfo extent
    identifier accessCondition
  ) ] );

  my %result;
  $result{numrecs} = $xml->{numberOfRecords};

  for (@{$xml->{records}->{record}}) {
    my $fields = _add_record_fields($_->{recordData});
    push(@{$result{records}}, $fields);
  }

  return \%result;
}

sub _get_records {
  my ($query_url, $param) = @_;

  my $ua = LWP::UserAgent->new();
  $ua->agent('Netscape/4.75');
  $ua->from('bd-tech@lub.lu.se');
  $ua->timeout(60);
  $ua->max_size(5000000);

  my $page = $param->{page} || 1;
  my $page_size = $param->{limit};
  my $start = $page_size ? (($page - 1) * $page_size + 1) : 1;
  my $chunk_limit = $page_size || cfg->{sru}{result_limit};
  my $total_hits;

  $query_url .= '&authorLimit=' . cfg->{sru}{author_limit};

  my $result;
  my $remaining = -1;
  while ($remaining != 0) {
    my $window = '';
    $window = "&startRecord=$start" if $start > 1;
    $window .= "&maximumRecords=$chunk_limit";

    say STDERR $query_url . $window if cfg->{debug_sru};

    my $sru_response = _get_sru_result($query_url . $window, $ua);
    my $chunk = _extract_mods($sru_response);

    $total_hits //= $chunk->{numrecs} || 0;

    if ($result) {
      push @{$result->{records}}, @{$chunk->{records}} if $chunk->{records};
    } else {
      $result = $chunk;
      $remaining = $result->{numrecs};
      $remaining = $page_size if $page_size && $remaining > $page_size;
    }

    if ($chunk->{records}) {
      my $chunk_size = @{$chunk->{records}};
      $remaining -= $chunk_size;
      $start += $chunk_size;
    } else {
      $remaining = 0;
    }

    if ($remaining < 0) {
      say STDERR "WARNING: $remaining remaining records in "
        . "RefMole::CiteList::_get_records for query\n$query_url\n";
      $remaining = 0;
    }
  }

  $param->{total_hits} = $total_hits;
  $param->{max_page} = $page_size ? ceil($total_hits / $page_size) : 1;

  return $result;
}

sub _get_sru_result {
  my ($query_url, $ua) = @_;

  my $req = HTTP::Request->new('GET', $query_url);
  return $ua->request($req)->content;
}

sub _multi_organization_criteria {
  my ($param, $param_name) = @_;

  $param->{$param_name} =~ s/\s//g;
  my @values = split ',', $param->{$param_name};
  return join ' or ', map { qq{$param_name exact $_} } @values;
}

sub _switch_author {
  my $author = shift;

  $author = "$2 $1" if $author =~ /(.*?),(.*)/;
  return $author;
}

sub trim {
  my $s = shift;
  $s =~ s/^\s+//;
  $s =~ s/\s+$//;
  return $s;
}

1;
