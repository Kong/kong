#!/usr/bin/env perl

# usage: commit-merge-explorer.pl next/1.3.0.x next/1.5.0.x
#
# Prints commits that are in 1.3 but not in 1.5 by commit message, not
# relying on hashes because rebases and cherrypicks mess them up sometimes

use strict;

sub main {
  my ($old, $new) = @_;
  my @all_commits = `git log --format="%s" $new`;
  my @to_merge_commits = `git log --format="%h %s" $old ^$new`;

  my $joined = join('|',
                    map { s/\s+\(\#\d+?\)\s+//g; quotemeta } # remove gh's added cherrypick number
                    @all_commits);

  print grep {!/$joined/} @to_merge_commits;
}

main @ARGV;
