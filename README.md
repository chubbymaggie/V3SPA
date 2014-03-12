V3SPA Angularized
=================
## Requirements

- nodejs
- npm
- python
- pip
- mongodb

To set up the environment:

    $ # OS X
    $ brew install node 

    $ # Fedora (v20)
    $ sudo yum install gcc kernel-devel kernel-headers dkms make bzip2 perl nodejs npm python-pip git python-devel mongodb-server
    $ pip install virtualenv
    $ mkdir vespa && cd vespa
    $ git init
    $ git clone http://gitlab.labs/v3spa/ide.git
    $ cd ide
    $ git submodule update --init
    $ sudo npm install -g gulp
    $ sudo npm install
    $ virtualenv vespa
    $ source vespa/bin/activate
    $ sudo pip install -r requirements.txt 

## Building 

All of the assets are now served from static/, but they aren't
actually stored there. The Grunt build system is responsible for
compiling assets and putting them in the right place.

To build assets:

    $ cd external/d3hive && npm install && gulp
    $ cd -
    $ gulp

To start the asset auto-reloader for development (you may need to
run just 'grunt' once first).

    $ gulp reloader

## Layout

All of the client side code is now located in src/. All external
libraries are in external.