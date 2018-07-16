#! /usr/bin/perl -w
#------------------------------------------------------
# pref.pl
# Perl script to parse the contents of XP/Vista Prefetch files
#
# usage: pref.pl [optoins] (see _syntax()]
# 
# Ref: http://www.42llc.net/index.php?option=com_myblog&Itemid=39
#
# Change History:
#   20091020 - removed full path for .pf file...was told that it could be 
#              too confusing
#   20090517 - updated output format for volume serial number
#              added TLN output
#		20090516 - added significant code
#
# copyright 2009 H. Carvey keydet89@yahoo.com
#------------------------------------------------------
use strict;
use Getopt::Long;
use Time::Piece;

my %config = ();
Getopt::Long::Configure("prefix_pattern=(-|\/)");
GetOptions(\%config, qw(vista|v dir|d=s file|f=s path|p server|s=s info|i tln|t csv|c help|?|h));

if ($config{help} || ! %config) {
	_syntax();
	exit 1;
}

if ($config{vista}) {
	$config{time_offset} = 0x80;
	$config{runcount_offset} = 0x98;
}
else {
	$config{time_offset} = 0x78;
	$config{runcount_offset} = 0x90;
}

my $server;
($config{server}) ? ($server = $config{server}) : ($server = "");

my @files;

if ($config{file}) {
	die $config{file}." not found.\n"
		unless (-e $config{file});
	die $config{file}." is not a file.\n"
		unless (-f $config{file});
	@files = $config{file};
}
elsif ($config{dir}) {
	my @list;
#	die $config{dir}." not found.\n"
#		unless (-e $config{dir});
#	die $config{dir}." is not a directory.\n"
#		unless (-d $config{dir});
	$config{dir} = $config{dir}."\/" unless ($config{dir} =~ m/\/$/);
#	print "DIR = ".$config{dir}."\n";
	opendir(DIR,$config{dir}) || die "Could not open ".$config{dir}.": $!\n";
	@list = grep{/\.pf$/} readdir(DIR);
	closedir(DIR);
	map {$files[$_] = $config{dir}.$list[$_]}(0..scalar(@list) - 1);
}
else {
	die "You have selected neither a directory nor a file.\n";
}

print join(',', qw/Filename Accessed Modified Created Run_count Last_run/), "\n"
	if ($config{csv});
foreach my $file (@files) {
	
	my @list = split(/\//,$file);
	my $i = scalar(@list) - 1;
	my $name = $list[$i];
	
	my ($access,$mod,$creation) = (stat($file))[8,9,10];
	my ($runcount,$runtime) = getMetaData($file);

	for my $stamp ($access,$mod,$creation,$runtime) {
		$stamp = localtime($stamp)->datetime;
		#$stamp = gmtime($stamp)->datetime;
		#$stamp =~ s/T/ /;	#if you rather have space
	}

	if ($config{csv}) {
		print join(',', $name, $access, $mod, $creation, $runcount, $runtime), "\n";	
	}
	elsif ($config{tln}) {
		print $runtime."|PREF|".$server."||".$name." last run (".$runcount.")\n";
	}
	else {
		printf "%-40s  %-24s (".$runcount.")\n",$file,$runtime;
		
		if ($config{info}) {
			my $name = getExeName($config{file});
			my %vib = getVibData($config{file});
			print "\n";
			print "EXE Name            : ".$name."\n";
			print "Volume Path         : ".$vib{volumepath}."\n";
			#print "Volume Creation Date: ".gmtime($vib{creationdate})." Z\n";
			print "Volume Creation Date: ".localtime($vib{creationdate})." Z\n";
			print "Volume Serial Number: ".$vib{volumeserial}."\n";
		}

		if ($config{path}) {
			my @paths = getFilepaths($config{file});
			print "\n";
			map{print $_."\n"}@paths;
		}
	}
}
	
#---------------------------------------------------------
# getExeName()
# get EXE name from .pf files
#---------------------------------------------------------
sub getExeName {
	my $file = $_[0];
	my $data;
	my $name;
	my $tag = 1;
	open(FH,"<",$file) || die "Could not open $file: $!\n";
	binmode(FH);
	seek(FH,0x10,0);
	while ($tag) {
		read(FH,$data,2);
		$tag = 0 if (unpack("v",$data) == 0);
		$name .= $data;
	}
	close(FH);
	$name =~ s/\00//g;
	return $name;
}


#---------------------------------------------------------
# getMetaData()
# get metadata from .pf files
#---------------------------------------------------------
sub getMetaData {
	my $file = $_[0];
	my $data;
	my ($runcount,$runtime);
	
	open(FH,"<",$file) || die "Could not open $file: $!\n";
	binmode(FH);
	seek(FH,$config{time_offset},0);
	read(FH,$data,8);
	my @tvals = unpack("VV",$data);
	$runtime = getTime($tvals[0],$tvals[1]);
	
	seek(FH,$config{runcount_offset},0);
	read(FH,$data,4);
	$runcount = unpack("V",$data);
	
	close(FH);
	return ($runcount,$runtime);
}

#---------------------------------------------------------
# getTime()
# Get Unix-style date/time from FILETIME object
# Input : 8 byte FILETIME object
# Output: Unix-style date/time
# Thanks goes to Andreas Schuster for the below code, which he
# included in his ptfinder.pl
#---------------------------------------------------------
sub getTime {
	my $lo = shift;
	my $hi = shift;
	my $t;

	if ($lo == 0 && $hi == 0) {
		$t = 0;
	} else {
		$lo -= 0xd53e8000;
		$hi -= 0x019db1de;
		$t = int($hi*429.4967296 + $lo/1e7);
	};
	$t = 0 if ($t < 0);
	return $t;
}

#---------------------------------------------------------
# getFilepaths()
# Get list of Unicode file paths embedded in the .pf file
#---------------------------------------------------------
sub getFilepaths {
	my $file = shift;
	my $data;
	my ($ofs,$size);
	my @paths;
	
	open(FH,"<",$file) || die "Could not open $file: $!\n";
	binmode(FH);
	seek(FH,0x64,0);
	read(FH,$data,8);
	($ofs,$size) = unpack("VV",$data);
	#printf "Offset:  0x%x  Size: $size\n",$ofs;

	seek(FH,$ofs,0);
	read(FH,$data,$size);
	close(FH);

	my @list = split(/\00\00/,$data);
#print "Strings = ".scalar(@list)."\n";
	foreach my $str (@list) {
		$str =~ s/\00//g;
		next if ($str eq "");
		push(@paths,$str);
	}
	return @paths;
}

#---------------------------------------------------------
# getVibData()
# Get volume information block data embedded in the .pf file
#---------------------------------------------------------
sub getVibData {
	my $file = shift;
	my $vib_ofs;
	my %vib_data;
	my $data;
	
	open(FH,"<",$file) || die "Could not open $file: $!\n";
	binmode(FH);
	seek(FH,0x6c,0);
	read(FH,$data,4);
	$vib_ofs = unpack("V",$data);
#	printf "VIB Offset = 0x%x\n",$vib_ofs;
	seek(FH,$vib_ofs,0);
	read(FH,$data,20);
#	my ($path_ofs,$path_ln,$time0,$time1,$sn) = unpack("V5",$data);
	my @vib = unpack("V5",$data);
	seek(FH,$vib_ofs + $vib[0],0);
	read(FH,$data,$vib[1] * 2);
	$data =~ s/\00//g;
	$vib_data{volumepath} = $data;
	$vib_data{creationdate} = getTime($vib[2],$vib[3]);
	
	my $str = uc(sprintf "%x",$vib[4]);
	my @sn = split(//,$str);
	$vib_data{volumeserial} = $sn[0].$sn[1].$sn[2].$sn[3]."-".$sn[4].$sn[5].$sn[6].$sn[7];
	close(FH);
	return %vib_data;
}

sub _syntax {
print<< "EOT";
pref [option]
Parse contents of XP/Vista Prefetch files/directory

  -v ............parse Vista Prefetch files (default: XP)
  -d directory...parse all files in directory
  -f file........parse a single Prefetch file
  -p ............list filepath strings (only with -f)
  -i ............list volume information block data
  -c ............Comma-separated (.csv) output (open in Excel)
                 Gets ONLY MAC times and runcount/last runtime
  -t ............get \.pf metadata in TLN format   
  -s server......add name of server to TLN ouput            
  -h ............Help (print this information)
  
Ex: C:\\>pref -v -f <path_to_Pretch_file>
    C:\\>pref -d C:\\Windows\\Prefetch -c

**All times printed as GMT/UTC

copyright 2009 H. Carvey
EOT
}
