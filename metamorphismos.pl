#!/usr/bin/perl -w
#
# Script which randomly places nodes and gives them a specific form based on the received coordinates
#
# Author: Dimitrios Zorbas (dim.zorbas(at)yahoo.com)
# Distributed under the GPLv2 (see LICENSE file)

use Math::Random;
use Math::Trig ':pi';
use GD::SVG;
use strict;

my $generate_images = 1;
my %nodes = ();
my ($terrain_x, $terrain_y) = (1280, 496); 	# change this according to the image dimensions (1x1 sq. decimeter = 1 pixel)

sub distance {
	my ($x1, $x2, $y1, $y2) = @_;
	return sqrt( (($x1-$x2)*($x1-$x2)) + (($y1-$y2)*($y1-$y2)) );
}

sub random_int {
	my $low = shift;
	my $high = shift;
	return Math::Random::random_uniform_integer(1, $low, $high);
}

(@ARGV==1) || die "usage: $0 <coordinates_file>\n";

my $coordinates_file = $ARGV[0];
open(FH, "<$coordinates_file") or die "Error: could not open coordinates file\n";


### READ POINT COORDINATES ###

my $num = 0;
my %points = ();
while (<FH>){
	chomp;
	$num++;
	my ($x, $y) = /([0-9]+\.[0-9]+)  ([0-9]+\.[0-9]+)/;
	#print "$num [$x $y]\n";
	$points{$num} = [$x, $y];
}

my $density = 1; 				# scale factor
my $norm_x = int($terrain_x * $density);	# normalised terrain_x
my $norm_y = int($terrain_y * $density); 	# normalised terrain_y

### GENERATE NODES ###

my %nodes_temp = ();
my %direction = ();
for(my $i=1; $i<=$num; $i++){
	my ($x,$y) = (random_int(1, $norm_x), random_int(1, $norm_y));

	while (exists $nodes_temp{$x}{$y}){
		($x, $y) = (random_int(1, $norm_x), random_int(1, $norm_y));
	}
	$nodes_temp{$x}{$y} = 1;
	$nodes{$i} = [$x, $y];

	my $min_angle = rand(2*pi);
	my $max_angle = rand(2*pi - $min_angle) + $min_angle;
	while (($max_angle - $min_angle) > pi/4){
		$min_angle = rand(2*pi);
		$max_angle = rand(2*pi - $min_angle) + $min_angle;
	}
	$direction{$i} = [$min_angle, $max_angle];
}

### START MOVING ###

draw_image(0) if ($generate_images == 1);
my $t = 1;
my %has_stopped = ();
my $detection_range = 50;	# in decimeters
my $comm_range = 150;		# in decimeters
my %occupied = ();
my %destination = ();
my %detected = ();
my %dont_detect = ();

while ($t > 0){
	print "#-# iteration $t #-#\n";

	# search for a destination point
	foreach my $n (keys %nodes){
		next if (exists $has_stopped{$n});
		my ($x, $y) = ($nodes{$n}[0], $nodes{$n}[1]);
		foreach my $p (keys %points){
			next if (exists $occupied{$p});
			my ($x_, $y_) = ($points{$p}[0], $points{$p}[1]);
			if (exists $destination{$n}){
				my ($xd, $yd) = ($points{$destination{$n}}[0], $points{$destination{$n}}[1]);
				if (distance($x, $x_, $y, $y_) <= distance($x, $xd, $y, $yd)){
					$destination{$n} = $p;
				}
			}else{
				if (distance($x, $x_, $y, $y_) <= $detection_range){
					$destination{$n} = $p;
					last;
				}
			}
		}
		if (!exists $destination{$n}){
			my $got = undef;
			foreach my $s (keys %has_stopped){
				next if (scalar keys %{$detected{$s}} == 0);
				next if (exists $destination{$n});
				my ($x_, $y_) = ($nodes{$s}[0], $nodes{$s}[1]);
				if (distance($x, $x_, $y, $y_) <= $comm_range){
					$got = $s;
					my $rn = int(rand(scalar keys %{$detected{$s}})) + 1;
					my $sel = 0;
					foreach my $p (keys %{$detected{$s}}){
						$sel++;
						if ($sel == $rn){
							$destination{$n} = $p;
							delete $detected{$s}{$p};
							last;
						}
					}
				}
			}
			if (exists $destination{$n}){
				print "# destination of $n is $destination{$n} (got this from $got)\n";
			}
		}	
	}

	# move randomly
	foreach my $n (keys %nodes){
		next if ((exists $destination{$n}) || (exists $has_stopped{$n}));
		move_node($n);
	}

	# go towards the selected destination point (if there is one)
	foreach my $n (keys %nodes){
		next if (!exists $destination{$n});
		my ($x, $y) = ($nodes{$n}[0], $nodes{$n}[1]);
		my $speed = 3 + rand(0.1);
		if (distance($points{$destination{$n}}[0], $x, $points{$destination{$n}}[1], $y) <= $speed){
			if (!exists $occupied{$destination{$n}}){
				($x, $y) = ($points{$destination{$n}}[0], $points{$destination{$n}}[1]);
				$has_stopped{$n} = 1;
				$occupied{$destination{$n}} = 1;
				foreach my $n_ (keys %destination){
					next if ($n_ == $n);
					if ($destination{$n_} == $destination{$n}){
						delete $destination{$n_};
					}
				}
			}
			delete $destination{$n};
		}else{
			($x, $y) = compute_location($points{$destination{$n}}[0], $points{$destination{$n}}[1], $x, $y);
		}
		$nodes{$n} = [$x, $y];
	}

	# if you have stopped, detect neighbouring points
	foreach my $n (keys %has_stopped){
		next if (exists $dont_detect{$n});
		my ($x, $y) = ($nodes{$n}[0], $nodes{$n}[1]);
		%{$detected{$n}} = ();
		foreach my $p ( keys %points){
			next if (exists $occupied{$p});
			my ($x_, $y_) = ($points{$p}[0], $points{$p}[1]);
			if (distance($x, $x_, $y, $y_) <= $detection_range){
				$detected{$n}{$p} = 1;
			}
		}
		if (scalar keys %{$detected{$n}} == 0){
			$dont_detect{$n} = 1;
		}
	}

	draw_image($t) if ($generate_images == 1);
	$t++;

	if ((scalar keys %has_stopped) == (scalar keys %points)){
		$t=-1;
	}
	printf "# moving=%d stopped=%d terminated=%d/%d\n", scalar keys %destination, scalar keys %has_stopped, scalar keys %dont_detect, scalar keys %nodes;
}

sub move_node {
	my $r = shift;
	my ($x0, $y0) = ($nodes{$r}[0], $nodes{$r}[1]);
	my ($x, $y) = (0, 0);
	my $speed = 3 + rand(0.1);
	my $check = 1;
	while ($check == 1){
		$check = 0;
		my $theta = rand($direction{$r}[1]-$direction{$r}[0]) + $direction{$r}[0];
		$x = $x0 + $speed*cos($theta);
		$y = $y0 + $speed*sin($theta);
		if (($x > ($norm_x-1)) || ($y > ($norm_y-1)) || ($x < 1) || ($y < 1)){
			$check = 1;
			my $min_angle = rand(2*pi);
			my $max_angle = rand(2*pi - $min_angle) + $min_angle;
			while (($max_angle - $min_angle) > pi/4){
				$min_angle = rand(2*pi);
				$max_angle = rand(2*pi - $min_angle) + $min_angle;
			}
			$direction{$r} = [$min_angle, $max_angle];
		}
	}
	$nodes{$r} = [$x, $y];
	#print "$r: was $x0 $y0 and is $x $y\n";
}

sub compute_location{
	my ($x1, $y1, $x0, $y0) = @_;
	my $speed = 3 + rand(0.1);
	my $x2 = undef;
	my $y2 = undef;
	if (($x0 - $x1) != 0){ ## avoid division by zero
		my $a = ($y0-$y1)/($x0-$x1);
		my $b = $y1 - $a*$x1;
		
		$x2 = ($speed**2 - (distance($x0, $x1, $y0, $y1) - $speed)**2 - $x0**2 - $y0**2 + $x1**2 + $y1**2 - 2*$b*$y1 + 2*$b*$y0)/(2*$x1 - 2*$x0 + 2*$a*$y1 - 2*$a*$y0);
		$y2 = $a*$x2 + $b;
	}else{
		$x2 = $x1;
		if ($y1 > $y0){
			$y2 = $y0 + $speed;
		}else{
			$y2 = $y0 - $speed;
		}
	}
	return ($x2, $y2);
}

sub draw_image {
	my $t = shift;
	my ($display_x, $display_y) = ($terrain_x, $terrain_y);
	my $im = new GD::SVG::Image($display_x, $display_y);
	my $white = $im->colorAllocate(255,255,255);
	my $green = $im->colorAllocate(0,255,0);
	my $black = $im->colorAllocate(0,0,0);
	my $red = $im->colorAllocate(255,0,0);
	my $blue = $im->colorAllocate(0,102,204);
	my $lblue = $im->colorAllocate(0,204,204);
	my $tyndall_blue = $im->colorAllocate(29, 66, 138);
# 	$im->transparent($white);
# 	$im->interlaced('true');
# 	my ($bsx, $bsy) = (350*$display_x/$norm_x, 310*$display_x/$norm_x);
# 	my $max_dist = 250;
	
# 	foreach my $p (keys %points){
# 		my ($x, $y) = ($points{$p}[0], $points{$p}[1]);
# 		($x, $y) = (int(($x * $display_x)/$norm_x), int(($y * $display_y)/$norm_y));
# 		my $d = distance($x, $bsx, $y, $bsy);
# 		$d = $max_dist if ($d > $max_dist);
# 		my $color = $im->colorAllocate(255,int(255-$d*255/$max_dist),0);
# 		$im->filledArc($x,$y,5,5,0,360,$color);
# 	}

	# inria image
# 	foreach my $r (keys %nodes){
# 		my ($x, $y) = ($nodes{$r}[0], $nodes{$r}[1]);
# 		($x, $y) = (int(($x * $display_x)/$norm_x), int(($y * $display_y)/$norm_y));
# 		if ((exists $has_stopped{$r}) && (exists $dont_detect{$r})){
# 			my $d = distance($x, $bsx, $y, $bsy);
# 			$d = $max_dist if ($d > $max_dist);
# 			my $color = $im->colorAllocate(255,int(255-$d*255/$max_dist),0);
# 			$im->filledArc($x,$y,5,5,0,360,$color);
# 		}elsif((exists $has_stopped{$r}) && (!exists $dont_detect{$r})){
# 			$im->filledArc($x,$y,5,5,0,360,$green);
# 		}elsif((!exists $has_stopped{$r}) && (!exists $dont_detect{$r})){
# 			$im->filledArc($x,$y,5,5,0,360,$black);
# 		}
# 	}

	# l3i
#	foreach my $r (keys %nodes){
#		my ($x, $y) = ($nodes{$r}[0], $nodes{$r}[1]);
#		my $color;
#		if ((exists $has_stopped{$r}) && (exists $dont_detect{$r})){
#			if (($x < 140) || ($x < 279) && ($y > 425)){
#				$color = $blue;
#			}else{
#				$color = $lblue;
#			}
#		}elsif((exists $has_stopped{$r}) && (!exists $dont_detect{$r})){
#			$color = $green;
#		}elsif((!exists $has_stopped{$r}) && (!exists $dont_detect{$r})){
#			$color = $black;
#		}
#		($x, $y) = (int(($x * $display_x)/$norm_x), int(($y * $display_y)/$norm_y));
#		$im->filledArc($x,$y,10,10,0,360,$color);
#	}

	# lakeside labs / Tyndall
	foreach my $r (keys %nodes){
		my ($x, $y) = ($nodes{$r}[0], $nodes{$r}[1]);
		my $color;
		if (exists $has_stopped{$r}){
			if (exists $dont_detect{$r}){
				$color = $black;
			}else{
				$color = $green;
			}
		}else{
			$color = $tyndall_blue;
		}
		($x, $y) = (int(($x * $display_x)/$norm_x), int(($y * $display_y)/$norm_y));
		$im->filledArc($x,$y,12,12,0,360,$color);
	}
	
	#$im->string(gdSmallFont, 10, $display_y-20, $t, $black); # legend

	my $image_file = undef;
	if ($t < 10){
		$t = join ('', "000", $t);
		$image_file = join('.', "time", $t, "svg");
	}elsif (($t >= 10) && ($t < 100)){
		$t = join ('', "00", $t);
		$image_file = join('.', "time", $t, "svg");
	}elsif (($t >= 100) && ($t < 1000)){
		$t = join ('', "0", $t);
		$image_file = join('.', "time", $t, "svg");
	}else{
		$image_file = join('.', "time", $t, "svg");
	}

	open(FILEOUT, ">$image_file") or
		die "could not open file $image_file for writing!";
	binmode FILEOUT;
	print FILEOUT $im->svg;
	close FILEOUT;
}


printf "# %s\n", '$Id: metamorphismos.pl 12 2016-12-14 10:48:57Z jim $';
exit 0;
