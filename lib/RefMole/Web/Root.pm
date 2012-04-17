package RefMole::Web::Root;

use Dancer ':syntax';

use RefMole::CiteList;

get '/' => sub {
  redirect '/create';
};

get '/cite' => sub {
  var page_title => 'Citation List';

  my $citations = RefMole::CiteList::get_publications(params);
  RefMole::CiteList::apply_csl($citations);

  ### TODO: Adapt template selection and ftype=js handling @ bup_sru 674-703

  template 'cite', { records => $citations->{records}, citations => $citations };
};

get '/create' => sub {
  var page_title => 'Embed Your Publication List in Your Homepage';

  template 'create';
};

get '/detail/:id' => sub {
  return redirect '/create' unless params->{id};

  template 'detail';
};

1;
