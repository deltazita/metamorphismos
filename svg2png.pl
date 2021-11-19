#!/usr/bin/perl -w

use strict;
use Cwd qw ( abs_path getcwd );

my $output = 1;
foreach my $file (@ARGV){
	$file = abs_path($file);

	my $t = $output;
	my $image_file = undef;
	if ($t < 10){
                $t = join ('', "000", $t);
                $image_file = join('.', $t, "png");
        }elsif (($t >= 10) && ($t < 100)){
                $t = join ('', "00", $t);
                $image_file = join('.', $t, "png");
        }elsif (($t >= 100) && ($t < 1000)){
                $t = join ('', "0", $t);
                $image_file = join('.', $t, "png");
        }else{
                $image_file = join('.', $t, "png");
        }

	my $exec = `inkscape -d 200 -b "#FFFFFF" -e $image_file $file &`;
	$output++;
}
