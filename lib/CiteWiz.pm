package CiteWiz;
use Dancer ':syntax';

get '/' => sub {
    template 'index';
};

post '/' => sub {
};

1;
