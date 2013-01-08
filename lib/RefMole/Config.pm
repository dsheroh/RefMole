package RefMole::Config;

use strict;
use warnings;
use 5.010;

use Config::Onion;
use FindBin '$RealBin';

use base 'Exporter';
BEGIN {
  our @EXPORT = ();
  our @EXPORT_OK = qw(
    cfg
    cfg_obj
  );
  our %EXPORT_TAGS = (
    all         => [ @EXPORT, @EXPORT_OK ],
  );
}

my $cfg_obj;
my @CONF_FILES = qw( refmole );

sub cfg { cfg_obj()->get }

sub cfg_obj { $cfg_obj //= load_cfg() }

sub load_cfg { Config::Onion->load(map { "$RealBin/../$_" } @CONF_FILES) }

