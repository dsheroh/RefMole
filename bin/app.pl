#!/usr/bin/env perl
use Dancer;
use all 'RefMole::';

my $cfg_obj = RefMole::Config->cfg_obj;
$cfg_obj->set_default(config);

dance;
