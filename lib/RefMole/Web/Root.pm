package RefMole::Web::Root;

use Dancer ':syntax';

use RefMole::CiteList;

get '/' => sub {
  redirect '/create';
};

get '/cite' => sub {
  var page_title => 'Citation List';

  my $citations = RefMole::CiteList::get_citations(params);
  RefMole::CiteList::apply_csl($citations);

  ### TODO: Adapt template selection and ftype=js handling @ bup_sru 674-703
  use Data::Dumper;
  $citations->{records} = Dumper($citations->{records});

  template 'cite', { citations => $citations };
};

get '/create' => sub {
  var page_title => 'Embed Your Publication List in Your Homepage';

  template 'create';
};

1;
