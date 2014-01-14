V3SPA Angularized
=================

## Requirements

- nodejs
- npm
- python
- pip

To set up the environment:

    $ # OS X
    $ brew install node 

    $ # Fedora
    $ sudo yum install npm

    $ # All
    $ sudo npm install -g grunt-cli
    $ # Install the local packages
    $ npm install
    $ mkvirtualenv vespa  # (optional, recommended, requires virtualenvwrapper)
    $ pip install -r requirements.txt

## Building 

All of the assets are now served from static/, but they aren't
actually stored there. The Grunt build system is responsible for
compiling assets and putting them in the right place.

To build assets:

    $ grunt

To start the asset auto-reloader for development (you may need to
run just 'grunt' once first).

    $ grunt watch

## Layout

All of the client side code is now located in src/. All external
libraries are in external.