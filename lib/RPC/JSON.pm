package RPC::JSON;

use warnings;
use strict;

use RPC::JSON::Shell;

use Carp;
use JSON;
use LWP::UserAgent;

use URI;
use URI::Heuristic qw(uf_uri);

use vars qw|$VERSION @EXPORT $DEBUG $META $AUTOLOAD|;

$VERSION = '0.01';

@RPC::JSON = qw|Exporter|;

@EXPORT = qw|
    shell
    test
|;

our $REQUEST_COUNT = 1;

sub shell {
    my ( $self ) = @_;
    RPC::JSON::Shell::shell();
}

my @options = qw|
    smd timeout keepalive env_proxy agent conn_cache max_size dont_connect
|;

sub new {
    my ( $class, @opts ) = @_;
    my $self = {};

    unless ( @opts ) {
        carp __PACKAGE__ . " requires at least the SMD URI";
        return 0;
    }

    #  ->new({ smd => $SMDURI, timeout => $TIMEOUT });
    if ( ref $opts[0] eq 'HASH' and @opts == 1 ) {
        foreach my $key ( @options ) {
            if ( exists $opts[0]->{$key} ) {
                $self->{$key} = $opts[0]->{$key};
            }
        }
    }
    #  ->new( smd => $SMDURI, timeout => $TIMEOUT );
    elsif ( @opts % 2 == 0 ) {
        my %p = @opts;
        my $i = 0;
        foreach my $key ( @options ) {
            if ( $opts[$i] eq $key ) {
                $self->{$key} = $opts[$i + 1];
                $i += 2;
            }
            last unless $opts[$i];
        }
        unless ( keys %$self ) {
            $self->{smd}     = $opts[0];
            $self->{timeout} = $opts[1];
        }
    }
    # Called like:
    #  ->new( $SMDURI, $TIMEOUT );
    elsif ( @opts < 2 ) {
        $self->{smd}     = $opts[0];
        $self->{timeout} = $opts[1];
    }
    bless $self, $class;

    # Verify the SMD is valid
    if ( $self->{smd} ) {
        my $smd = $self->{smd};
        delete $self->{smd};
        $self->set_smd($smd);
    }

    unless ( $self->{smd} ) {
        carp "No valid SMD source, please check the SMD URI.";
        return 0;
    }
    # Default timeout of 180 seconds
    $self->{timeout} ||= 180;

    unless ( $self->{dont_connect} ) {
        # If we fail to connect, it will alert the user but we shouldn't cancel
        # the object (or maybe we should if it is a 40* error?)
        $self->connect;
    }
    return $self;
}

sub set_smd {
    my ( $self, $smd ) = @_;
    my $uri;
    eval {
        if ( $smd =~ /^\w+:/ ) {
            $uri = new URI($smd);
        } else {
            $uri = uf_uri($smd);
        }
    };
    if ( $@ or not $uri ) {
        carp $@;
        return 0;
    }
    $self->{smd} = $uri;
}

sub connect {
    my ( $self, $smd ) = @_;
    if ( $smd ) {
        $self->set_smd($smd);
    }
    my %options =
        map  { $_ => $self->{$_} }
        grep { $_ !~ '^smd|dont_connect$' and exists $self->{$_} }
        @options;
    $self->{_ua} = LWP::UserAgent->new( %options );
    if ( $self->{_ua} and $self->{smd} ) {
        my $response = $self->{_ua}->get( $self->{smd} );
        
        if ( $response and $response->is_success ) {
            return $self->load_smd($response);
        }

        carp "Can't load $self->{smd}: " . $response->status_line;
    }
    return 0;
}

=item load_smd

load_smd will process a given SMD file by converting from JSON to a Perl
native structure, and setup the various keys as well as the autoload handles
for calling the methods.

=cut

sub load_smd {
    my ( $self, $res ) = @_;
    my $content = $res->content;
    # Turn this on, because a lot of sources don't properly quote keys
    local $JSON::BareKey  = 1;
    local $JSON::QuotApos = 1;
    my $obj;
    eval { $obj = jsonToObj($content) };
    if ( $@ ) { 
        carp $@;
        return 0;
    }
    if ( $obj ) {
        $self->{_service} = { methods => [] };
        foreach my $req ( qw|serviceURL serviceType objectName SMDVersion| ) {
            if ( $obj->{$req} ) {
                $self->{_service}->{$req} = $obj->{$req};
            } else {
                carp "Invalid SMD format, missing key: $req";
                return 0;
            }
        }
        unless ( $self->{_service}->{serviceURL} =~ /^\w+:/ ) {
            my $serviceURL = sprintf("%s://%s%s",
                $self->{smd}->scheme,
                $self->{smd}->authority,
                $self->{_service}->{serviceURL});
            $self->{_service}->{serviceURL} = $serviceURL;
        }
        $self->{serviceURL} = new URI($self->{_service}->{serviceURL});

        $self->{methods} = {};
        foreach my $method ( @{$obj->{methods}} ) {
            if ( $method->{name} and $method->{parameters}  ) {
                push @{$self->{_service}->{methods}}, $method;
                $self->{methods}->{$method->{name}} = $self->{_service}->{methods}->[-1];
            }
        };
    }
    return 1;
}

=item service

Return the object name of the current service connected to, or undef if
not connected.

=cut

sub service {
    my ( $self ) = @_;
    if ( $self->{_service} and $self->{_service}->{objectName} ) {
        return $self->{_service}->{objectName};
    }
    return undef;
}

=item methods

Return a structure of method names for use on the current service, or undef
if not connected.

The structure looks like:
    {
        methodName1 => [ { name => NAME, type => DATATYPE }, ... ]
    }

=cut

sub methods {
    my ( $self ) = @_;
   
    if ( $self->{_service} and $self->{_service}->{methods} ) {
        return {
            map { $_->{name} => $_->{parameters} }
            @{$self->{_service}->{methods}}
        };
    }
    return undef;
}

=item serviceURI

Returns the serviceURI (not the SMD URI, the URI to request RPC calls against),
or undef if not connected. 

=cut

sub serviceURI {
    my ( $self ) = @_;
    if ( $self->{serviceURL} ) {
        return $self->{serviceURL};
    }
    return undef;
}

sub bind {
    my ( $self, $method, $obj, $dest_method ) = @_;
    $self->{bindings} ||= {};
    if ( $obj and $dest_method ) {
        $self->{bindings}->{$method} ||= [];
        push @{$self->{bindings}->{$method}},
            sub { $obj->$dest_method(@_); };
    }
}

sub listen {
    my ( $self, $method, $dest_method ) = @_;
    if ( $dest_method ) {
        $self->{bindings}->{$method} ||= [];
        push @{$self->{bindings}->{$method}},
            sub { $dest_method->(@_); };
    }
}

sub AUTOLOAD {
    my $self = shift;
    my ( $l ) = $AUTOLOAD;
    $l =~ s/.*:://;
    if ( exists $self->{methods}->{$l} ) {
        my ( @p ) = @_;
        my $packet = {
            id     => $REQUEST_COUNT++,
            method => $l,
            params => [ @p ]
        };
        my $res = $self->{_ua}->post(
            $self->{serviceURL}->as_string,
            Content_Type => 'application/javascript+json',
            Content      => objToJson($packet)
        );
        if ( $res->is_success ) {
            my $ret = {};
            eval { $ret = jsonToObj($res->content); };
            if ( $@ ) {
                carp "Error parsing server response, but got acceptable status: $@";
            } else {
                if ( $ret->{result} ) {
                    my $result = jsonToObj($ret->{result});
                    if ( $self->{bindings}->{$l} ) {
                        foreach my $binding ( @{$self->{bindings}->{$l}} ) {
                            &{$binding}($result);
                        }
                    }
                    return $result;
                }
            }
        } else {
            carp "Error received from server: " . $res->status_line;
        }
    }
    return undef;
}

=head1 AUTHORS

Copyright 2006 J. Shirley <jshirley@gmail.com>

This program is free software;  you can redistribute it and/or modify it under
the same terms as Perl itself.  That means either (a) the GNU General Public
License or (b) the Artistic License.

=cut

1;
