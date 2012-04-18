package RefMole::CiteList;

use strict;
use warnings;
use 5.010;

use Dancer qw( config debug );

### BEGIN ORMS LIFE-SUPPORT ###
use lib config->{sbcat_path} . '/lib/extension';
use lib config->{sbcat_path} . '/lib/default';
use luurCfg;
use Orms;
use Cwd;
my $cfg;
BEGIN {
  $ENV{HOSTNAME} //= `hostname --fqdn`;
  my $original_path = getcwd;
  chdir config->{sbcat_path};
  $cfg = new luurCfg;
  chdir $original_path;
}
### END ORMS LIFE-SUPPORT ###

use CSL;
use Encode;
use LWP::UserAgent;
use XML::Simple;

sub apply_csl {
  my ($publications) = @_;

  my $csl = CSL->new(cfg => config);
  my $citations = $csl->process($publications->{style}, $publications);

  my $i;
  my %ref_map;
  $ref_map{$_->{id}} = $i++ for @$citations;

  for my $rec (@{$publications->{records}}) {
    my $sort_nr = $ref_map{$rec->{recordid}};
    next unless defined $sort_nr;

    $rec->{sort_nr}  = $sort_nr;
    $rec->{citation} = $citations->[$sort_nr]{citation};
  }

  @{$publications->{records}} =
    sort { ($a->{sort_nr} || 0) <=> ($b->{sort_nr} || 0) }
    @{$publications->{records}};

  # Return nothing because $publications was modified in-place
  return;
}

sub get_detail {
  my %param = @_;

  return unless $param{id};

  my $query_url = config->{sru}{url}
    . "&query=id%20exact%20%22$param{id}%22";
  my $sru_response = _get_sru_result($query_url);
  my $result = _extract_mods($sru_response);

  $result->{records}[0]{id} = $param{id};
  $result->{style} = $param{style} || config->{csl_engine}{default_style};

  return $result;
}

sub get_publications {
  my %param = @_;

  my $conditions;
  my ($author_style, $author_sort_order, $hiddenlist);

  if ($param{author}) {
    $conditions = "_basic%20exact%20%22$param{author}%22";

### TODO: Enable following code after new attributes have been added to our
### ORMS db

=pod
    my $luur = Orms->new($cfg->{ormsCfg});
    my $o;
    $o->{$_} = $luur->getObject($_) for qw( luAuthor luLdapId );
    my ($luAuthorOId) = @{
      $luur->getObjectsByAttributeValues(
        type            => $o->{'luAuthor'},
        attributeValues => {$o->{'luLdapId'} => $param{author}}
      )
    };

    if ($luAuthorOId) {
      $author_style = lc $luur->getAttributeValue(
        object  => $luAuthorOId,  attribute => 'citationStyle'
      );
      $author_sort_order = lc $luur->getAttributeValue(
        object  => $luAuthorOId,  attribute => 'sortDirection'
      );
      $hiddenlist = $luur->getRelatedObjects(
        object2  => $luAuthorOId, relation  => 'isHiddenFor'
      );
    }
=cut

  } elsif ($param{dept}) {
    $conditions = "department=$param{department}";
  } else {
    return {};
  }

  $conditions .= "AND%20PublishingYear%3D%22$param{publyear}%22"
    if $param{publyear};

  $conditions .= "AND%20documentType%3D%22$param{doctype}%22"
    if $param{doctype};

  my $query_url = config->{sru}{url}
    . "&query=$conditions&sortKeys=publishingYear,,0";

  ### TODO: If unlimited result set sizes are needed, adapt "paging the result"
  ### loop from lines 520-559 of bup_sru.pl
  my $remaining = $param{limit} || config->{sru}{result_limit};
  $query_url .= "&maximumRecords=$remaining";
  my $sru_response = _get_sru_result($query_url);
  my $result = _extract_mods($sru_response);

  if ($param{author}) {
    $result->{norm_author} = _switch_author($param{author});
    $result->{list_author} = $param{author};

    ### TODO: Compare results against "delete hidden publications" loop @
    ### bup_sru.pl 568-584
    if ($hiddenlist) {
      my %hidden = map { $_ => 1 } @$hiddenlist;
      for (reverse 0 .. $result->{numrecs}) {
        if ($hidden{$result->{records}[$_]{recordid}}) {
          splice(@{$result->{records}}, $_, 1);
        }
      }
    }
  }

  $result->{style} = lc $param{style} || $author_style || 'apa';

  $result->{list_dept} = $param{dept} if defined $param{dept};

  $result->{records} = _sort_records($result->{records}, \%param)
    if $result->{numrecs} > 1;

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
    my $role = $entity->{role}[0]{roleTerm}{content};
    next unless $role;

    $role = 'author' if $role eq 'reviewer';

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
    } elsif ($role eq 'department') {
      push @{$result{affiliation}}, $entity->{namePart};
    } elsif ($role eq 'project') {
      push @{$result{project}}, $entity->{namePart};
    } elsif ($role eq 'research group') {
      push @{$result{researchgroup}}, $entity->{namePart};
    }
  }

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
        $entry->{prange} .= ' - ' . $_->{end} unless ref $_->{end};
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

    push @{$result{$related->{type}}}, $entry if $entry;
  }

  return \%result;
}

sub _extract_mods {
  my ($mods_xml) = @_;

  my $parser = XML::Simple->new;

  my $xml = $parser->XMLin($mods_xml,
    forcearray => [
      'record', 'subject', 'relatedItem', 'detail', 'note', 'abstract',
      'name', 'role', 'titleInfo', 'extent', 'identifier'
    ]
  );

  my %result;
  $result{numrecs} = $xml->{numberOfRecords};

  for (@{$xml->{records}->{record}}) {
    my $fields = _add_record_fields($_->{recordData});
    push(@{$result{records}}, $fields);
  }

  return \%result;
}

sub _get_sru_result {
  my ($query_url) = @_;

  my $ua = LWP::UserAgent->new();
  $ua->agent('Netscape/4.75');
  $ua->from('bd-tech@lub.lu.se');
  $ua->timeout(60);
  $ua->max_size(5000000);

  my $req = HTTP::Request->new('GET', $query_url);
  return $ua->request($req)->content;
}

sub _sort_records {
  my ($records, $param) = @_;
  ### TODO: Adapt from sorting routine @ bup_sru 625-670

  return $records;
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
