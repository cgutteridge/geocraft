package Minecraft::Config;

sub load_config
{
	my( $file ) = @_;
	my $return;
	unless ($return = do $file) {
		warn "couldn't parse $file: $@" if $@;
		warn "couldn't do $file: $!"    unless defined $return;
		warn "couldn't run $file"       unless $return;
		exit 1;
	}
}

1;
