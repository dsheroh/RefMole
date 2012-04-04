package CiteWiz;
use Dancer ':syntax';

get '/create' => sub {
  var page_title => 'Embed Your Publication List in Your Homepage';

  template 'embed_form';
};

get '/' => sub {
  template 'index';
};

1;
