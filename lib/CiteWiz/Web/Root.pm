package CiteWiz::Web::Root;

use Dancer ':syntax';

use CiteWiz::CiteList;

get '/' => sub {
  redirect '/create';
};

get '/cite' => sub {
  var page_title => 'Citation List';

  template 'cite', { citations => CiteWiz::CiteList::get_citations(params) };
};

get '/create' => sub {
  var page_title => 'Embed Your Publication List in Your Homepage';

  template 'create';
};

1;
