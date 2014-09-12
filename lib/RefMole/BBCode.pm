package RefMole::BBCode;

use strict;
use warnings;

use base 'Exporter';
BEGIN {
  our @EXPORT = qw();
  our @EXPORT_OK = qw(
    render_bbcode
    render_bbtitle
    strip_bbcode
    strip_bbtitle
  );
  our %EXPORT_TAGS = (
    all         => [ @EXPORT, @EXPORT_OK ],
  );
}

use Parse::BBCode;

my $render_bbc;
my $strip_bbc;
my $strip_title_bbc;
my $title_bbc;

sub render_bbcode {
  $render_bbc ||= Parse::BBCode->new({tags => {Parse::BBCode::HTML->defaults,
    sub   => '<sub>%{parse}s</sub>',
    sup   => '<sup>%{parse}s</sup>',
  }});

  return $render_bbc->render($_[0]);
}

sub render_bbtitle {
  $title_bbc ||= Parse::BBCode->new({ tags => {
    i     => '<i>%{parse}s</i>',
    b     => '<b>%{parse}s</b>',
    u     => '<u>%{parse}s</u>',
    sub   => '<sub>%{parse}s</sub>',
    sup   => '<sup>%{parse}s</sup>',
  }});

  return $title_bbc->render($_[0]);
}

sub strip_bbcode {
  $strip_bbc ||= Parse::BBCode->new({
    tags => {
      '*'   => '%{parse}s',
      b     => '%{parse}s',
      code  => '%{parse}s',
      color => '%{parse}s',
      email => '%{parse}s',
      i     => '%{parse}s',
      img   => '%{parse}s',
      list  => '%{parse}s',
      quote => '%{parse}s',
      size  => '%{parse}s',
      sub   => '[%{parse}s]',
      sup   => '[%{parse}s]',
      u     => '%{parse}s',
      url   => '%{parse}s', 
    },
    text_processor => sub { return $_[0] // '' },
  });

  return $strip_bbc->render($_[0]);
}

sub strip_bbtitle {
  $strip_title_bbc ||= Parse::BBCode->new({
    tags => {
      i     => '%{parse}s',
      b     => '%{parse}s',
      u     => '%{parse}s',
      sub   => '[%{parse}s]',
      sup   => '[%{parse}s]',
    },
    text_processor => sub { return $_[0] // '' },
  });

  return $strip_title_bbc->render($_[0]);
}

1;

