# necroperl 

## Build Status

[![Build Status](https://travis-ci.org/fredericorecsky/necroperl.svg?branch=master)](https://travis-ci.org/fredericorecsky/necroperl)

## installing

curl -L https://raw.githubusercontent.com/fredericorecsky/necroperl/master/bin/install_necroperl | sh

## About

Necroperl is a set of scripts that I build to help myself when
developing perl code on a new environment. 

Usually I develop  the code to run on whatever remote computer
but I *prefer* edit it locally as much as I can. The workflow is
like this:

* on my home dir on my machine assembly all files necessary
* get the remote configuration from db connections to any other
connection that is required.
* assembly a bunch of ssh tunnels
* work locally

## So what each tool does?

necroperl ->  runs the program on remote server, slurp the IO and 
show on my local terminal.

```
necroperl -host remotehost or ssh config alias
```

This host should be accessible without password!

```
necroperl script.pl
```

This will run the script on remote host defined above. It will rsync
the source code to remote server, and run it with ssh as well to define
PERL5LIB and other necessary variables.

dev_tunnels -> create ssh tunnels and keep a list of them

It is mainly to keep track of the tunnels already opened. If the process
of tunnel is dead, it will show it as red when listing.



