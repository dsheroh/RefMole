package RefMole::Web::Root;

use Dancer ':syntax';

use RefMole::CiteList;

get '/' => sub {
  redirect '/create';
};

get '/cite' => sub {
  var page_title => 'Citation List';

  my $citations = RefMole::CiteList::get_publications(scalar params);
  RefMole::CiteList::format_citations($citations) if $citations->{numrecs};

  if (params->{ftyp}) {
    for my $cite (@{$citations->{records}}) {
      chomp $cite->{citation};

      $cite->{title} =~ s/'/\\'/g;
      $cite->{title} =~ s/"/\\"/g;

      for my $rel (@{$cite->{relation}}) {
        if ($rel->{title}) {
          $rel->{title} =~ s/'/\\'/g;
          $rel->{title} =~ s/"/\\"/g;
        }
      }
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
  $tokens->{uri_base} = request->base->path eq '/' ? '' : request->base->path;
};

1;
