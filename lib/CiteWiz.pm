package CiteWiz;
use Dancer ':syntax';

get '/' => sub {
  redirect '/create';
};

get '/cite' => sub {
  var page_title => 'Citation List';

  template 'cite';
};

get '/create' => sub {
  var page_title => 'Embed Your Publication List in Your Homepage';

  template 'create';
};

1;
