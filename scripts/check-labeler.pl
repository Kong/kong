#!/usr/bin/env perl

# Script to verify that the labeler configuration contains entries for
# all plugins.  If any plugins are missing, the script errors out and
# prints the missing entries.

# The pre- and post-function plugins are tracked together under the
# label "plugins/serverless-functions".  Special code is present below
# to ensure that the label exists.

use strict;

die "usage: $0 <labeler-config-file>\n" unless ($#ARGV == 0);

my $labeler_config = $ARGV[0];

-f $labeler_config
    or die "$0: cannot find labeler config file $labeler_config\n";

my %plugins = ( "plugins/serverless-functions", "plugins/serverless-functions:\n- kong/plugins/pre-function\n- kong/plugins/post-function\n\n" );
for my $path (<kong/plugins/*>, <plugins-ee/*>) {
    my $plugin = $path =~ s,kong/,,r;
    $plugins{$plugin} = "$plugin:\n- $path/**/*\n\n" unless ($plugin =~ m,plugins/(pre|post)-function,);
}

open(LABELER_CONFIG, "<", $labeler_config) or die "$0: can't open labeler config file $labeler_config: $!\n";
while (<LABELER_CONFIG>) {
    delete $plugins{$1} if (m,^(plugins.*):,);;
}
close(LABELER_CONFIG);

exit 0 unless (keys %plugins);

print STDERR "Missing plugins in labeler configuration $labeler_config.\n";
print STDERR "Please add the following sections to the file:\n\n";
for my $plugin (sort keys %plugins) {
    print STDERR $plugins{$plugin};
}

exit 1;
