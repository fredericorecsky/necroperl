package Necromancer;

use strict;
use warnings;

use Cwd qw/abs_path cwd getcwd/;
use Data::Dumper;
use File::Basename;
use IPC::Open3;
use IO::Select;
use Module::CoreList;
use Module::ScanDeps;
use Symbol 'gensym';
use Sys::Hostname;

=head1 NAME

Necromancer - Black magic and scripts to automate perl development

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

necromancer install the module Necromancer and the 
necromancer cli that works as a frontend to the 
functions

Perhaps a little code snippet.

    use Necromancer;

    my $foo = Necromancer->new();
    ...

=cut

=head1 METHODS

=head2 Necromancer->new()

    Create a new necromancer object

=cut 

my $config_directory = $ENV{ HOME } . "/.necroperl/";

sub new {
    my ( $class, $args ) = @_;

    my $self_args = ref $args eq "HASH" ? $args : {};

    my $self = {
        ( %{ $self_args } ),
        work_cmd            => abs_path( $0 ),
        cwd                 => getcwd,
        cmd                 => $0,
        name                => 'rperl',
        #remote              => undef,
        args                => [ @ARGV ],
        debug               => 0,
        dependencies        => [],
        localhost           => hostname(),
        action              => "rperl",
        config_dir          => $config_directory,
        cfg_remote_host     => $config_directory . "cfg_remote_host",
        cfg_remote_dir      => $config_directory . "cfg_remote_dir",
        cfg_dev_tunnels     => $config_directory . "ssh_tunnel",
    };

    bless $self, $class; 

    if ( ! -e $self->{ config_dir } ) {
        mkdir $self->{ config_dir } 
            or die "necroperl config directory does not exist and can't be created\n";
    }

    $self->{ perl } ||= "perl";

    if ( $self->{ compile } ) {
        $self->{ perl } .= " -c";
    }

    $self->_input_file;
    $self->_remote_dir;
    $self->_git_top_level;

    if ( ! $self->{ remote } ) {
        $self->host;
    }

    return $self;
}

# Load the key, from cfg file, if fatal is true will die on error

sub _load_cfg {
    my ( $self, $key, $cfg, $fatal ) = @_;

    open my $fh, "<", $self->{ $cfg } or ( ( $fatal && die "$@\n" ) || return );
        $self->{ $key } = <$fh>;
    close $fh;

    return $self->{ $key };
}

sub _write_cfg { }

sub _input_file {
    my ( $self ) = @_;

    $DB::single = 1;
    if ( ! $self->{ file } && $self->{ remote_args } && @{ $self->{ remote_args } } ) {
        if ( -e $self->{ remote_args }[0] ){
            ( $self->{ file } ) = shift @{ $self->{ remote_args } };
        }
    }
    
    if ( $self->{ file } ) {
        $self->{ file_abs_path } = abs_path( $self->{ file } );
        if ( -d $self->{ file_abs_path } ) {
            $self->{ dir_abs_path } = $self->{ file_abs_path };
        } else {
            $self->{ dir_abs_path } = dirname( $self->{ file_abs_path } );
        }
    }
}

sub _remote_dir {
    my ( $self )  = @_;
    if ( ! defined $self->{ remote_dir } ) {
        $self->_load_cfg( 'remote_dir', 'cfg_remote_dir' );
    }
}


# todo remote dir and host
sub _set_remote_dir {
    my ( $self ) = @_;
    
    $self->host();

    if ( ! defined $self->{ remote_dir } ){
        unlink $self->{ cfg_remote_dir };
    } else {
        my @cmd = (
            'ssh', $self->{ remote }, 'cd', $self->{ remote_dir },
        );

        my ( $status ) = $self->execute( @cmd );
        if ( $status ) {
            die "[$status] Remote Directory $self->{ remote_dir } does not exists";
        }
        open my $fh, ">", $self->{ cfg_remote_dir } or die;
            print $fh $self->{ remote_dir };
        close $fh;
    }
    undef $self->{ remote_dir };
    $self->_remote_dir;
    print "Set remote_dir to $self->{ remote_dir }\n";
}


sub _requires_file {
    my ( $self ) = @_;

    if ( ! $self->{ file } || ! -e $self->{ file } ){
        die "One of parameters should be a valid perl script\n";
    }
}

sub _git_top_level {
    my ( $self ) = @_;

    chdir $self->{ dir_abs_path } if $self->{ dir_abs_path };
    $self->{ git_tree } = `git rev-parse --show-toplevel 2>/dev/null`;
    chomp $self->{ git_tree };

    return if ( ! $self->{ dir_abs_path } && ! $self->{ git_tree } );


    if ( ! $? ) {
        while( cwd ne '/' ){
            if ( -e ".fperl_git" ) {
                $self->{ git_tree } = cwd();
            }
            chdir( ".." );
        }
    } else {
        warn "there is not .fperl_git_file\n" if ! -e "$self->{ git_tree }/.fperl_git";
    }

    if ( $self->{ remote_dir } && $self->{ file } ) {
        $self->{ run_path } =
            $self->{ remote_dir } .
            substr(
                dirname( $self->{ file_abs_path } ),
                length( dirname( $self->{ git_tree } )),
            );
        $self->{ run_file } = basename( $self->{ file } );
    }else{
        $self->{ run_path } = $self->{ cwd };
        $self->{ run_file } = $self->{ file };
    }

    chdir $self->{ cwd };
    
}

sub _git_modified_files {
    my ( $self ) = @_;

    return if ! $self->{ git_tree };

    chdir $self->{ git_tree };
    @{ $self->{ git_modified } } = `git ls-files -m`;
    chdir $self->{ cmd };
}

sub _dependencies {
    my ( $self ) = @_;

    my $dependencies = scan_deps(
        files => [ $self->{ file_abs_path } ],
        recurse => 2,
    );

    for my $module ( keys %{ $dependencies } ) {
        next if $module eq $self->{ file };
        next if ( $dependencies->{ $module }{ type } ne "module" );
        my $package = $module;

        $package =~ s/\//\:\:/g;
        $package =~ s/\.pm$//;

        my $filename = $dependencies->{ $module }{ file };

        my $core = 1;
        if ( ! Module::CoreList::is_core( $package ) ) {
            $core = 0;
            push @{ $self->{ dependencies } }, {
                package     => $package,
                module      => $module,
                filename    => $filename,
                core        => $core,
            }
        }
        push @{ $self->{ all_dependencies } }, {
            package     => $package,
            module      => $module,
            filename    => $filename,
            core        => $core,
        }
    }
}

sub _rsync {
    my ( $self )  = @_;

    my $remote_dir = $self->{ remote_dir } ? 
                     $self->{ remote_dir } :
                    dirname( $self->{ git_tree } );
    print "Prepare for $self->{ file } from $self->{ cwd } @ $self->{ remote } on $remote_dir \n" if $self->{ verbose };

    my $remote_mkdir = `ssh $self->{ remote } mkdir -p $remote_dir`;
    my $sync_cmd = "rsync --exclude=.git --cvs-exclude -a $self->{ git_tree } $self->{ remote }:$remote_dir --delete";
    print $sync_cmd if $self->{ verbose };
    my $sync = qx/$sync_cmd/;
    if ( $? ) {
        die "$?\nError when syncing $self->{ remote }:$remote_dir \n";
    }else{
        print "Synced to $self->{ remote }:$remote_dir\n" if $self->{ verbose };
    }
}

sub check_host {
    my ( $self, $host ) = @_;

    die "Requires a hostname\n" if ! $host;
   
    # todo check ssh config
    my $run = `ssh $host exit`;

    if ( $? ) {
        die <<EOF;
    The host: $host is offline or not configured on 
    ssh config file. Please check your ssh config on 
    $ENV{HOME}/.ssh/config.
EOF
    }else{
        return 1;
    }
}

sub config {
    my ( $self ) = @_;
    print Dumper $self;
}

# check host
sub host {
    my ( $self, $remote ) = @_;

    if ( ! $self->{ remote } && $remote ) {
        $self->{ remote } = $remote;
    }

    if ( $self->{ remote } && $self->check_host( $self->{ remote } ) ) {
        open my $fh, ">", $self->{ cfg_remote_host } or die "$@\n";
            print $fh $self->{ remote };
        close $fh;

        print "Actual default remote host:  $self->{ remote } \n";
        $self->_load_cfg( 'remote', 'cfg_remote_host', "fatal" );
    }else {
        $self->_load_cfg( 'remote', 'cfg_remote_host' );
    }

    return $self->{ remote };
}

sub remote_dir {
    $_[0]->_set_remote_dir();
}

sub dep {
    my ( $self ) = @_;

    $self->_dependencies();

    if ( @{ $self->{ dependencies } } ){
        print "Base: $self->{ file_abs_path }\n";
        print join "\n", (
            map { $_->{ core } . "\t" . $_->{ package } . "\t" . $_->{ filename } }
            @{ $self->{ dependencies } }
        ), '';
    } else {
        print "No local dependencies found for this module\n";
    }
}

sub alldep {
    my ( $self ) = @_;

    $self->_dependencies();

    if ( @{ $self->{ all_dependencies } } ){
        print "Base: $self->{ file_abs_path }\n";
        print join "\n", (
            map { $_->{ core } . "\t" . $_->{ package } . "\t" . $_->{ filename } }
            @{ $self->{ all_dependencies } }
        ), '';
    } else {
        print "No local dependencies found for this module\n";
    }
}

sub changed {
    my ( $self ) = @_;

    $self->_git_modified_files();

    if ( ref $self->{ git_modified } eq "ARRAY" ){
        print join "\n", @{ $self->{ git_modified } }, "\n";
    }
}

sub remote {} #deprecated
sub slurp {} # deprecated

sub run { rperl( @_ ) }

sub rperl {
    my ( $self ) = @_;

    die "Need a remote machine defined ! \n" if ! $self->{ remote };
    die "Need a command to run !\n" if ! $self->{ file };
    
    $self->_rsync();

    $self->{ io_sync } = 1;

    my @cmd = (
        'ssh', $self->{ remote }, 
        'export RPERL_PID=$$;', 
        ( $self->{ verbose } ? (
                'echo -n "Remote Shell PID:";',
                'echo $RPERL_PID;',
            ) : (
                'echo -n;'
            )
        ),
        "export PERL5LIB=$self->{ run_path }/lib:\$PERL5LIB ;", 
        'cd', $self->{ run_path }, ';',
        $self->{ perl }, $self->{ run_file },  @{ $self->{ remote_args } }, ';', 
        'pgrep -P $RPERL_PID;',
        'echo',
        );

    print join " " ,@cmd , "\n" if $self->{ verbose };

    my ( $status, $stdout, $stderr ) = $self->execute( @cmd );
    if ( $status ) {
        print "Error $status when running $self->{ file }\n";
        print join " ", @cmd, "\n";
    }
}

sub help {
    print "Rockstar table tennis\n";
}

sub execute {
    my ( $self, @cmd ) = @_;

    my ( $wtr, $rdr, $err, $pid );
    $err = gensym();

    eval {
        $pid = open3( $wtr, $rdr, $err, @cmd );
    };
    die "$@\n" if $@;

    my $sel = IO::Select->new;
    $sel->add( $rdr, $err );

    my ( $stdout, $stderr );

    while ( my @ready = $sel->can_read ) {
        for my $fh ( @ready ) {
            my $line;
            my $len = sysread $fh, $line, 4096;
            if ( $len == 0 ) {
                $sel->remove( $fh );
                next;
            } else {
                if ( $fh == $rdr ) {
                    $stdout .= $line;
                    print $line if $self->{ io_sync };
                    next;
                }
                if ( $fh == $err ) {
                    $stderr .= $line;
                    warn $line if $self->{ io_sync };
                    next;
                }
            }
        }
    }

    waitpid( $pid, 0 );

    return (( $? >> 8 ), $stdout, $stderr );
}


sub load_tunnels {
    my ( $self ) = @_;
    open my $fh , "<" , $self->{ cfg_dev_tunnels } 
        or die "$self->{ cfg_dev_tunnels }, $!, $@ \n";

    my $order = 0;
    while ( my $line = <$fh> ) {
        chomp $line;
        my ( $local_port, $hostname, $remote_port, $jump_host, $pid, $alias ) = split( /\t/, $line );
        $self->{ local_port }{ $local_port } = {
            host => $hostname,
            remote_port => $remote_port,
            jump_host => $jump_host,
            pid => $pid,
            alias => $alias || undef,
            order => $order,
        };
        $order ++;
    }
    close $fh;
}


1; # End of Necromancer
