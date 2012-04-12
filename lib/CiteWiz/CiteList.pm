package CiteWiz::CiteList;

use strict;
use warnings;
use 5.010;

use Dancer 'config';

### BEGIN ORMS LIFE-SUPPORT ###
use lib config->{sbcat_path} . '/lib/extension';
use lib config->{sbcat_path} . '/lib/default';
use luurCfg;
use Orms;
use Cwd;
my $cfg;
BEGIN {
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

  my $limit = $param{limit} // 0;

  if ($param{author}) {
    $conditions = "_basic%20exact%20%22$param{author}%22";

    my $luur = Orms->new($cfg->{ormsCfg});
    my $o;
    $o->{$_} = $luur->getObject($_) for qw( luAuthor personNumber );
    ### TODO: Should 'personNumber' be changed to 'lucat' or something here?
    my ($luAuthorOId) = @{
      $luur->getObjectsByAttributeValues(
        type            => $o->{'luAuthor'},
        attributeValues => {$o->{'personNumber'} => $param{author}}
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

  return {%param, conditions => $conditions,};
}

1;
