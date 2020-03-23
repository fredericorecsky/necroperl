package Messages;

use strict;
use warnings;

use Exporter 'import';
our @EXPORT_OK = qw/msg_text/;

my %messages = ();

$messages{ raise_format } = <<EOF;
The raise address argument is not valid.

It needs to be on the format:
    scheme://host/path

Examples:
    ssh://192.168.0.1:~/devel/
EOF

sub msg_text {
    my ( $identifier ) = @_;

    print $messages{ $identifier };

}


1;

