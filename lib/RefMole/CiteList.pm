package RefMole::CiteList;

use strict;
use warnings;
use 5.010;

use Dancer qw( config debug );

use LWP::UserAgent;
use XML::Simple;

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

sub get_citations {
  my %param = @_;

  my $conditions;
  my ($style, $sort_order, $hiddenlist);

  if ($param{author}) {
    $conditions = "_basic%20exact%20%22$param{author}%22";

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
      $style = $luur->getAttributeValue(
        object  => $luAuthorOId,  attribute => 'citationStyle'
      );
      $sort_order = $luur->getAttributeValue(
        object  => $luAuthorOId,  attribute => 'sortDirection'
      );
      $hiddenlist = $luur->getRelatedObjects(
        object2  => $luAuthorOId, relation  => 'isHiddenFor'
      );
    }
  } elsif ($param{dept}) {
    $conditions = "department=$param{department}";
  } else {
    return {};
  }

  $conditions .= "AND%20PublishingYear%3D%22$param{publyear}%22"
    if $param{publyear};

  $conditions .= "AND%20documentType%3D%22$param{doctype}%22"
    if $param{doctype};

  my $query_url = config->{cite}{sru_url}
    . "&query=$conditions&sortKeys=publishingYear,,0";
  debug $query_url;

  ### TODO: If unlimited result set sizes are needed, adapt "paging the result"
  ### loop from lines 520-559 of bup_sru.pl
  my $remaining = $param{limit} || config->{cite}{result_limit};
  $query_url .= "&maximumRecords=$remaining";
  my $sru_response = _get_sru_result($query_url);
  debug $sru_response;
  my $result = _extract_mods($sru_response);
  debug $result;

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

  ### Continue here

  return {
    %param,
    conditions => $conditions,
    query_url  => $query_url,
  };
}

sub _add_record_fields {
  ### TODO: Implement based on buo_sru sub add_record_fields
  return @_;
}

sub _extract_mods {
  my ($mods_xml) = @_;

  my $parser = XML::Simple->new;

  ### Probably not needed thanks to Dancer, but it's in bup_sru.pl.
  ### Uncomment if there are encoding issues.
  #utf8::upgrade($mods_xml);

  my $xml = $parser->XMLin( $mods_xml,
    forcearray => [
      'record', 'subject', 'relatedItem', 'detail', 'note', 'abstract',
      'name', 'role', 'titleInfo', 'extent', 'identifier'
    ]
  );

  my %result;
  $result{numrecs} = $xml->{numberOfRecords};

  for (@{$xml->{records}->{record}}) {
    my $fields = _add_record_fields(\$_->{recordData});
    push(@{$result{records}}, $_);
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

sub _switch_author {
  ### TODO: Implement based on bup_sru.pl sub switch_author
  return @_;
}

1;
