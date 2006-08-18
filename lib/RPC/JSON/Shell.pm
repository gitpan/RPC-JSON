package RPC::JSON::Shell;

use warnings;
use strict;

use vars qw|$VERSION @EXPORT $DEBUG $META $AUTOLOAD|;

$VERSION = '0.01';

@RPC::JSON::Shell = qw|Exporter|;

use RPC::JSON;
use Term::ReadLine;
use Data::Dumper;

my $rpcInstance;

sub shell {
    my ( $self ) = @_;
    my $term   = new Term::ReadLine 'RPC::JSON::Shell';
    my $prompt = "Not connected > ";
    my $out    = $term->OUT || \*STDOUT;

    while ( defined ( $_ = $term->readline($prompt) ) ) {
        s/^\s+|\s+$//g;
        my ( $method, @args ) = split(/\s+/, $_);
        $method = lc($method);
        if ( __PACKAGE__->can($method) ) {
            __PACKAGE__->$method($out, @args);
        }
        elsif ( $method =~ /^quit|exit$/ ) {
            return 1;
        } elsif ( exists $rpcInstance->methods->{$method} ) {
            __PACKAGE__->method($out, $method, @args);
        } else {
            print $out "Unrecognized command, type help for a list of commands\n";
        }
        if ( $rpcInstance and $rpcInstance->service ) {
            $prompt = sprintf("%s > ", $rpcInstance->service);
        } else {
            $prompt = "Not connected > ";
        }
    }
}

sub help {
    my ( $class, $out, @args ) = @_;
    print $out qq|
RPC::JSON::Shell Help
---------------------
Below is a full listing of commands, and how they can be used:
    connect <URI> - Connect to a URI, must be an SMD.
    disconnect    - Close connection to a specific URI (if connected)

    ls            - List available methods
    <method> LIST - Call method with parameters LIST 

    quit          - Exit RPC::JSON::Shell
|;

}

=item connect smdUrl

Connect to the specified SMD URL

=cut

sub connect {
    my ( $class, $out, @args ) = @_;
    if ( @args == 1 ) {
        if ( $rpcInstance ) {
            print $out "Closing previous RPC connection\n";
        }
        $rpcInstance = new RPC::JSON({ smd => $args[0] });
        unless ( $rpcInstance ) {
            print $out "Can't connect to $args[0], check specified URI\n";
            return 0;
        }
    } else {
        print $out "Usage: connect <URI>\n";
    }
}

=item disconnect

If connected, will disconnect from the existing service.  This doesn't
necessarily mean that it will disconnect the socket (it will if the socket is
still open), because JSON-RPC does not require a dedicated connection.

=cut

sub disconnect {
    my ( $class, $out, @args ) = @_;
    if ( $rpcInstance and $rpcInstance->service ) {
        print $out "Disconnecting from " . $rpcInstance->serviceURI . "\n";
        $rpcInstance = undef;
    }
}

=item quit

Aliased to disconnected

=cut

=item ls

List available methods

=cut

sub ls {
    my ( $class, $out, @args ) = @_;
    if ( $rpcInstance and $rpcInstance->service ) {
        my $methods = $rpcInstance->methods;
        if ( $methods and ref $methods eq 'HASH' and %$methods ) {
            foreach my $method ( keys %$methods ) {
                my $params = join(" ",
                    map { "$_->{name}:$_->{type}" }
                    @{$methods->{$method}});
                print $out "\t$method: $params\n";
            }
        } else {
            print $out "Service seems empty (No Methods?)\n";
        }
    } else {
        print $out "Connect first (use connect <uri>)\n";
    }
}

=item Method Caller

By entering <method> [parameters] the shell will query the Service and display
results

=cut

sub method {
    my ( $self, $out, $method, @args ) = @_;

    if ( $rpcInstance and $rpcInstance->service and $method ) {
        if ( ( my $result = $rpcInstance->$method(@args) ) ) {
            print $out Dumper($result);
        } else {
            print $out "Can't call method $method\n";
        }
    } else {
        print $out "Connect first (use connect <uri>)\n";
    }
}

=head1 AUTHORS

Copyright 2006 J. Shirley <jshirley@gmail.com>

This program is free software;  you can redistribute it and/or modify it under
the same terms as Perl itself.  That means either (a) the GNU General Public
License or (b) the Artistic License.

=cut

1;
