package RefMole::Dancer::Root;

use Dancer ':syntax';

use RefMole::CiteList;
use RefMole::Config 'cfg';

get '/' => sub {
  redirect '/create';
};

my %dirty_param = map { $_ => 1 } qw( ftyp page max_page total_hits );

get '/cite' => sub {
  var page_title => 'Citation List';

  my $citations = RefMole::CiteList::get_publications(scalar params);
  RefMole::CiteList::format_citations($citations) if $citations->{numrecs};

  if (params->{max_page} > 1) {
    my %params = params;
    my $clean_params = join ';', map { $_ . '=' . $params{$_} }
      grep { !$dirty_param{$_} } sort keys %params;
    var clean_params => $clean_params;
  }

  if ((params->{ftyp} // '') eq 'js') {
    for my $cite (@{$citations->{records}}) {
      chomp $cite->{citation};
      $cite->{citation} =~ s/'/\\'/g;
      $cite->{citation} =~ s/"/\\"/g;
    }

    content_type 'application/javascript';
    template 'js_citewriter',
      { records => $citations->{records}, citations => $citations },
      { layout => undef };
  } else {
    template 'cite',
      { records => $citations->{records}, citations => $citations };
  }
};

get '/create' => sub {
  var page_title => 'Embed Your Publication List in Your Homepage';

  if (my $rec_ids = params->{record}) {
    $rec_ids =~ tr/0-9,//cd;
    var record => $rec_ids;
  }

  template 'create';
};

get '/detail/:id' => sub {
  my $rec = RefMole::CiteList::get_detail(scalar params);
  RefMole::CiteList::format_citations($rec) if $rec->{numrecs};

  var page_title => $rec->{records}[0]{title}[0] || 'No record found';

  template 'detail', { entry => $rec->{records}[0], records => $rec };
};

hook 'before_template_render' => sub {
  my $tokens = shift;
  $tokens->{cfg} = cfg;
  $tokens->{uri_base} = request->base->path eq '/' ? '' : request->base->path;
  $tokens->{author_limit} = config->{sru}{author_limit};
  $tokens->{extra_author_text} = config->{sru}{extra_author_text};
};

1;
