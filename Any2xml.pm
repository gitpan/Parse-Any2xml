# Copyright 2001,2002 Reliance Technology Consultants, Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

package Parse::Any2xml;

use strict;
use warnings;
use re 'eval';

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT = (qw(parse));
our $VERSION = '2.01';

## Code:

## Debug levels. Initially 0, may be set by elements to different things,
## stays at a level until changed (global scope, you see?).
## These levels are done differently than other levels; they are done as bits,
## much as chmod does its permissions.
## Available level bits:
##  0  - Show no verbose output.
##  1  - Show elements as they are entered and exited.
##  2  - Show important attributes as they are entered and exited.
##  4  - Show regexes as they are found and matched upon.
##  8  - Show text as it is matched upon.
##  16 - Show Perl as it is to be evaluated (e.g. _expr, _set).
##  32 - Show pseudo-elements (children that are not nodes).
my $debug_level = 0;

sub parse {
  my ($xtmpl, $input) = @_;
  return 
    fix_multiple_roots(
      get_content({
        content => $xtmpl },
        [$input]));
}

sub fix_multiple_roots {
  my ($xml) = @_;
  my @root;
  for (my $i = 0; $i < @$xml; $i++) {
    next unless ref $xml->[$i];
    next if $xml->[$i]{tag_type};
    push @root, $xml->[$i];
    delete $xml->[$i];
  }
  push @$xml, shift @root;
  foreach (@root) {
    push @{$xml->[-1]{content}}, @{$_->{content}};
  }
  return $xml;
}
  
sub xml_routine {
  my ($tag,$text) = @_;
  my @ret;
  while (my @mem = get_match($tag,\$text)) {
    push (@ret,{tag_name=>$tag->{tag_name},
      content=>get_content($tag,\@mem), 
      attrib=>get_attrib($tag,\@mem),
      tag_type=>($tag->{attrib}{'_fill'}||$tag->{attrib}{'%fill'})?undef:$tag->{tag_type}});
  }
  return \@ret;
}

sub get_match {
  my ($tag,$text) = @_;
  debug_attrib($tag,'match');
  my $regex = $tag->{attrib}{'_match'}||$tag->{attrib}{'%match'}||"(?s)(.+)";
  debug(4,"regex: |$regex|");
  if ($$text and $$text =~ /$regex/) {
    debug(8,"text: |$$text|\nmatch: |$&|");
    my @mem;
    die "ASSERT" unless ( scalar (@+) == scalar (@-) );
    for (my $i = 1; $i < scalar (@+); $i++) {
      push (@mem,substr ($$text,$-[$i], ($+[$i] - $-[$i]) ));
    }
    $$text = $';
    return @mem;
    #return ($1,$2,$3,$4,$5,$6,$7,$8,$9);
  }
  return ();
}

sub get_attrib {
  my $tag = shift;
  my $mem = shift;
  my %attrib;
  foreach (keys %{$tag->{attrib}}) {
    if (my $name = is_dyn_attrib($_)){
      debug_attrib($tag,"set_$name");
      $attrib{$name} = get_text($tag->{attrib}{'_set_'.$name}||$tag->{attrib}{'%set_'.$name},$mem);
    } elsif (not is_reserved_attrib($_)) {
      debug_attrib($tag,$_);
      $attrib{$_} = $tag->{attrib}{$_};
    }
  }
  return \%attrib;
}

sub get_content {
  my $tag = shift;
  my $mem = shift;
  if (exists $tag->{attrib}{'_debug-level'}) {
    $debug_level = $tag->{attrib}{'_debug-level'};
  }
  if ($tag->{attrib}{'%fill'}||$tag->{attrib}{'_fill'}) {
    $tag->{tag_type} = undef;
    debug_attrib($tag,'exp');
    return [get_text($tag->{attrib}{'_exp'}||$tag->{attrib}{'%exp'},$mem) ];
  }
  my @content;
  foreach (@{$tag->{content}}) {
    if (ref and (not defined $_->{tag_type} or $_->{tag_type} eq 'empty')) {
      debug(1,"element-enter: |$_->{tag_name}|");
      debug_attrib($_,'set');
      my $tags = xml_routine( $_, get_text($_->{attrib}{'_set'}||$_->{attrib}{'%set'},$mem) );
      foreach (@$tags) {
        debug(1,"element-exit: |$_->{tag_name}|");
      }
      push (@content,@$tags);
    } else {
      debug(32,"pseudo-element: |$_|");
      push (@content,$_);
    }
  }
  return \@content;
}

sub get_text {
  my ($code,$mem) = @_;
  if ($code) {
    debug(16,"initial code: |$code|");
     $code =~ s/\$(\d+)/\$mem->[$1-1]/g;
    debug(16,"final code: |$code|");
     {
       local $SIG{"__DIE__"};
       my $val = eval $code;
       die $@ if ($@);
       return $val;
     }
   # if (ref (my $func = eval $code) eq 'CODE') {
   #   $func->(@$mem);
   # } else {
   #   $code =~ s/\$(\d)/\$mem->[\$1-1]/g;
   #   return eval $code;
   # }
  } else {
    return $mem->[0];
  }
}

sub is_dyn_attrib {
  my $attrib = shift;
  return $1 if ($attrib =~ /_set_(.*)/);
  return $1 if ($attrib =~ /\%set_(.*)/);
}

sub is_reserved_attrib {
  my $attrib = shift;
  return 1 if ($attrib =~ /^_/);
  return 1 if ($attrib =~ /^%/);
}

## Debugging
sub debug {
  my ($level,$msg) = @_;
  if ($debug_level & $level) {
    print STDERR "$msg\n";
  }
}

sub debug_attrib {
  my ($node,$attrib) = @_;
  if (exists $node->{attrib}{$attrib}) {
    debug(2,"attribute |$attrib|: |$node->{attrib}{$attrib}|");
  }
  if (exists $node->{attrib}{'_'.$attrib}) {
    debug(2,"attribute |_".$attrib."|: |".$node->{attrib}{'_'.$attrib}."|");
  }
  if (exists $node->{attrib}{'%'.$attrib}) {
    debug(2,"attribute |%".$attrib."|: |".$node->{attrib}{'%'.$attrib}."|");
  }
}

'Why must all requires return true?';

__END__
=head1 NAME

Parse::Any2xml - Parse text into XML

=head1 SYNOPSIS

  use Parse::Any2xml;
  $ximple_tree = parse( $xtmpl, $text );

=head1 DESCRIPTION

Uses a template to make formatted, poorly formatted, or unformatted text into
well-formed XML.

=head1 EXPORT

parse: <xtmpl> String -> <ximple_tree>
Use the XML template to parse the string and return the resultant XML.

=head1 XTMPL

You should code at least one element within the root element.  Whether to use
elements or attributes is your choice. To code attributes use the _set_foo
directive discussed below.  Any attribute you code without the _set prefix is
passed through by Parse::Any2xml.

All Any2XML directives are prefixed with a _ . Your attributes can start with
an underscore, provided they do not clash with the defined directives.

=head2 Parse::Any2xml attributes

=over

=item _match - Pattern match and extract
      
_match is an optional tag. By default "(.*)" is its value. It specifies a
regular expression including memory and any inline switches. 

Thus 
  <newelement _set="$6" _set_abcd="$1*25"_fill="1"/> 
 is same as 
  <newelement _set="$6" _match="(.*)" _set_abcd="$1*25"_fill="1"/> 
  
Unlike Perl's maximum of 9 memory variables ($1 .. $9), here you have unlimited 
memory variables, i.e. you can have $15, $20 etc. according to your match 
expression. 
         
Example: C<_match="(?is)name:\s*(.*?)\n\s*address:\s*(.*?)\n">
        
=item _set - Source for Match

Sets the source that needs to be parsed (or further evaluated) according to
the _match directive. This value is usually a matched memory value from a
previous higher level match.

Note that its value is a valid Perl expression to be evaluated using eval().

Example: C<_set="$1.'-'.$2">
        
      
=item _set_foo - set Attribute foo

Allows creation of attribute with the name 'foo'.

Example: C<_set_amount="$3+$4-$5">

=item _exp - Perl expression 

This sets the contents of an element if and only if _fill is used; it is
ignored if _fill is not used. The contents of the element will be the result of
this Perl expression.

=item _fill - Fill Element 

Fill the current element using _exp if it exists, otherwise _set . Without this
Parse::Any2xml will create an empty element. Using _fill destroys data such
that an element's child will not be able to match on it.

 Example 1: <address _set="$4" _fill="1">
 Example 2: <company _set="$2" _set_name="$1" _exp="'Got'.$1.'Hooray'" _fill="1">

=back

=item _debug-level - Print debugging/verbosity

Accepts a level number that ranges from 0 to 63, printing lots of information
each time. The number is actually a bitwise number, much like chmod takes for
permissions, so take any from the following table and add them together for
your desired level of debugging.

=over

=item 0 - Nothing.

=item 1 - Non-textual children (elements).

=item 2 - Useful attributes.

=item 4 - Regexes.

=item 8 - Input text that is being matched on.

=item 16 - Perl.

=item 32 - Textual children (content).

=back

=item Double-quoted Expressions
        
All values specified in double quotes for C<_match>, C<_set>, and C<_exp> are 
C<eval()>ed as Perl code. So any legal Perl code is allowed in here. So if you
code any literals, you need to code them within single quotes and concatenate
with any expressions used. Perl's rules in escaping special characters apply
here. If the return value is a null or numeric or character zero, the value
returned is null (i.e. "").  If you want to see a space or zero instead,
concatenate a space or zero in front of the result.

=head1 SUPPORT

=over

=item Mailing List

<http://goreliance.com/mailman/listinfo/parse-any2xml-list>

=item Web site

<http://goreliance.com/devel/parse-any2xml>

=back

=head1 AUTHOR

  Reliance Technology Consultants, Inc. <http://goreliance.com>
  (Mike MacHenry <dskippy@ccs.neu.edu>)

=head1 SEE ALSO

L<XML::Ximple>

=cut
