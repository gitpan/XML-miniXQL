#!/usr/bin/perl -w
use strict;
use lib '/home/sergeant/perl/lib';
use vars qw/$htmlfile $xmlfile $outputfile $help $verbose $p $xml $html/;

#########################
# XMERGE
#########################
# This script merges an XML source file
# with an XML data file. I use this to
# generate my CV, both statically on the
# command line, and dynamically on the web.
# For the web, the form parameters you
# need are 'htsrc' and 'xmsrc' or 'xml'
# See http://sergeant.org for an example of usage


use XML::Parser;
use XML::miniXQL;
use Data::Dumper;
use CGI;
use Getopt::Long;

sub usage;

my %optctl = (
	'htmlfile' => \$htmlfile,
	'xmlfile' => \$xmlfile,
	'outputfile' => \$outputfile,
	'help' => \$help,
	'verbose' => \$verbose,
	);

# Option types
my @options = (
	'htmlfile=s',
	'xmlfile=s',
	'outputfile=s',
	"help",
	"verbose",
	);

if ($ENV{GATEWAY_INTERFACE}) {
	# Using CGI
	$p = new CGI;
	print $p->header;
	$htmlfile = $p->param('htsrc');
	$xmlfile = $p->param('xmsrc');
	$xml = $p->unescape($p->param('xml'));
}
else {
	GetOptions(\%optctl, @options) || die "Get Options Failed";
	if ($help || !($htmlfile && $xmlfile)) {
		usage;
	}
	if ($outputfile) {
		open(STDOUT, ">$outputfile") or die "Can't output to $outputfile: $!";
	}
}

$/ = undef;

open(HTML, $htmlfile) or die "Can't read html file $htmlfile: $!";
$html = <HTML>;
close HTML;

if (!$xml) {
	open(XML, $xmlfile) or die "Can't read xml file $htmlfile: $!";
	$xml = <XML>;
	close XML;
}

if ($ENV{GATEWAY_INTERFACE}) {
	if ($p->param('delxml')) {
		unlink $xmlfile;
	}
}

my $searcher = new XML::Parser(
	Style=>'Stream',
	Namespaces => 1,
	Pkg=>'Searcher',
	ErrorContext => 2,
	);

# Process of compiling the files:
#	- Parse the html - get searches out
#	- Process searches against XML - get results
#	- Parse the html again - output replaced bits.

my $searches;
eval {
	$searches = $searcher->parse($html);
#	print "Searches:\n", $#{$searches}, "\n", (join "\n", @{$searches});
#	print "\n\n";
};
if ($@) {
	die $@ . " in search of $htmlfile";
}

# OK - Got our searches - now use XML::miniXQL to retrieve values...
my $results = XML::miniXQL::queryXML($xml, @{$searches});
if (!ref $results) {
	die "Query of $xmlfile failed\n";
}

# warn "Results: ", Dumper($results), "\n";

# Got matches - now re-parse html putting in replacements...

my $replacer = new XML::Parser(
	Style=> 'Stream',
	Pkg => 'Replacer',
	Namespaces => 1,
	Replacements => $results, # Gets passed to $expat
	ErrorContext => 2,
	);

eval {
	$replacer->parse($html);
};
if ($@) {
	die $@ . " in replacement of $htmlfile";
}


sub usage {
	print <<EOT;
Usage:
	xmerge -xmlfile <filename> -htmlfile <filename> [-outputfile <filename>] [-verbose] [-help]
EOT
	exit(0);
}

########################################################
# Searcher

package Searcher;

sub StartDocument {
	my $expat = shift;
	@{$expat->{searchfor}} = ();
}

sub StartTag {
	my $expat = shift;
	my $element = shift;
	my %attribs = %_;

	if ($expat->namespace($element) eq 'http://www.sergeant.org/xmerge') {
		if ($element eq 'repeat') {
			$expat->{repeat} = 1;
		}
		elsif ($element eq 'replace') {
			my $search = $attribs{name};
			$search .= '*' if $expat->{repeat};
			push @{$expat->{searchfor}}, $search;
		}
		elsif ($element eq 'attrib') {
			my $search = $attribs{query};
			$search .= '*' if $expat->{repeat};
			push @{$expat->{searchfor}}, $search;
		}
		else {
			warn "Unknown xmerge element: $element\n";
		}
	}
}

sub EndTag {
	my $expat = shift;
	my $element = shift;

	if ($expat->namespace($element) eq 'http://www.sergeant.org/xmerge') {
		if ($element eq 'repeat') {
			$expat->{repeat} = 0;
		}
	}
}

sub Text {
}

sub EndDocument {
	my $expat = shift;
	return $expat->{searchfor};
}


########################################################
# Replacer

package Replacer;

sub encode {
	my $string = shift;
	$string =~ s/&/&amp;/g;
	$string =~ s/</&lt;/g;
	$string =~ s/>/&gt;/g;
	$string =~ s/'/&apos;/g;
	$string =~ s/"/&quot;/g;
	$string;
}

sub maketag {
	my $open = shift;
	my $element = shift;
	my ($attribs) = @_;
	my $tag = "<" . ($open ? '' : '/') . $element;
	if (defined $attribs) {
		foreach (keys (%{$attribs})) {
			$tag .= " " . encode($_) . '="' . encode($attribs->{$_}) . '"';
		}
	}
	$tag .= ">";
}

sub StartTag {
	my $expat = shift;
	my $element = shift;
	my %attribs = %_;

	if ($expat->namespace($element) eq 'http://www.sergeant.org/xmerge') {
		if ($element eq 'replace') {
			if ($expat->{repeat}) {
				if (!$expat->{numrepeat}) {
					if ($expat->{repeat} > 0) {
						$expat->{numrepeat} = $expat->{repeat};
					}
					else {
						eval {
							$expat->{numrepeat} = scalar @{$expat->{Replacements}->{$attribs{name}}};
						};
					}
				}
				$expat->{html} .= maketag(1, $element, \%attribs);
			}
			else {
				eval {
					print shift @{$expat->{Replacements}->{$attribs{name}}};
				};
			}
		}
		elsif ($element eq 'repeat') {
			$expat->{repeat} = $attribs{max} || -1; # -1 is true
			$expat->{html} = "<repeater>";
		}
		elsif ($element eq 'attrib') {
			if ($expat->{repeat}) {
				if (!$expat->{numrepeat}) {
					if ($expat->{repeat} > 0) {
						$expat->{numrepeat} = $expat->{repeat};
					}
					else {
						eval {
							$expat->{numrepeat} = scalar @{$expat->{Replacements}->{$attribs{query}}};
						};
					}
				}
				$expat->{html} .= maketag(1, $element, \%attribs);
			}
			else {
				eval {
					$expat->{attribname} = [$attribs{name}, shift @{$expat->{Replacements}->{$attribs{query}}}];
					delete $attribs{name};
					delete $attribs{query};
					my $tag = $attribs{tag};
					delete $attribs{tag};
					$expat->{attribtag} = $tag;
					%attribs = (%attribs, @{$expat->{attribname}});
					print maketag(1, $tag, \%attribs);
				};
			}
		}
	}
	else {
		if ($expat->{repeat}) {
			$expat->{html} .= maketag(1, $element, \%attribs);
		}
		else {
			print;
		}
	}
}

sub EndTag {
	my $expat = shift;
	my $element = shift;

	if ($expat->namespace($element) eq 'http://www.sergeant.org/xmerge') {
		if ($element eq 'repeat') {
			$expat->{repeat} = 0;
			# OK - now we have to parse the repeat section as many times as we
			# have repeats.
			$expat->{html} .= "</repeater>";
#			print "Repeat ", $expat->{numrepeat}, " times\n";
#			print "Repeating section:\n--\n", $expat->{html}, "\n--\n";

			my $repeater = new XML::Parser(
				Style=> 'Stream',
				Pkg => 'Repeater',
				Namespaces => 0, # Already blatted all our namespaces :-(((
				Replacements => $expat->{Replacements}, # Gets passed to $expat
				ErrorContext => 2,
				);

			for (my $i = 0; $i < $expat->{numrepeat}; $i++) {
				eval {
					$repeater->parse($expat->{html});
				};
				if ($@) {
					die "Repeater failed with $@";
				}
			}
			$expat->{html} = '';
			$expat->{numrepeat} = 0;
		}
		elsif ($element eq 'attrib') {
			if ($expat->{repeat}) {
				$expat->{html} .= maketag(0, $element);
			}
			else {
				print maketag(0, $expat->{attribtag});
				delete $expat->{attribtag};
			}
		}
		elsif ($expat->{repeat}) {
			$expat->{html} .= maketag(0, $element);
		}
	}
	else {
		if ($expat->{repeat}) {
			$expat->{html} .= maketag(0, $element);
		}
		else {
			print;
		}
	}
}

sub Text {
	my $expat = shift;

	if ($expat->{repeat}) {
		$expat->{html} .= encode($_);
		return;
	}
	else {
		print;
	}
}

########################################################
# Repeater

package Repeater;

sub StartTag {
	my $expat = shift;
	my $element = shift;
	my %attribs = %_;

	if ($element eq 'replace') {
		print shift @{$expat->{Replacements}->{$attribs{name}}};
	}
	elsif ($element ne 'repeater') {
		print;
	}

}

sub EndTag {
	my $expat = shift;
	my $element = shift;

	if ($element ne 'replace' && $element ne 'repeater') {
		print;
	}
}

1;

__END__
