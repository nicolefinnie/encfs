#!/usr/bin/perl

# Benchmark EncFS against eCryptfs

use File::Temp;
use warnings;

#require("tests/common.pl");
require("common.pl");


# Create a new empty working directory
sub newWorkingDir {
    my $prefix     = shift;
    my $workingDir = mkdtemp("$prefix/encfs-performance-XXXX")
      || die("Could not create temporary directory");

    return $workingDir;
}

sub cleanup {
    print "cleaning up...";
    my $workingDir = shift;
    system("umount $workingDir/ecryptfs_plaintext");
    system("fusermount -u $workingDir/encfs_plaintext");
    system("rm -Rf $workingDir");
    print "done\n";
}

sub mount_encfs {
    my $workingDir = shift;

    my $c = "$workingDir/encfs_ciphertext";
    my $p = "$workingDir/encfs_plaintext";

    mkdir($c);
    mkdir($p);

    delete $ENV{"ENCFS6_CONFIG"};
    #system("./build/encfs --extpass=\"echo test\" --standard $c $p > /dev/null");
    system("encfs --extpass=\"echo test\" --standard $c $p > /dev/null");

    waitForFile("$c/.encfs6.xml") or die("Control file not created");

    print "# encfs mounted on $p\n";

    return $p;
}

sub mount_ecryptfs {

    if(system("which mount.ecryptfs > /dev/null") != 0) {
        print "skipping ecryptfs\n";
        return "";
    }

    my $workingDir = shift;

    my $c = "$workingDir/ecryptfs_ciphertext";
    my $p = "$workingDir/ecryptfs_plaintext";

    mkdir($c);
    mkdir($p);

    system("expect -c \"spawn mount -t ecryptfs $c $p\" mount-ecryptfs.expect > /dev/null") == 0
      or die("ecryptfs mount failed - are you root?");

    print "# ecryptfs mounted on $p\n";

    return $p;
}

sub benchmark {
    my $dir = shift;
    our $linuxgz;

    my @results = ();
    my @writeResult = ();
    my @untarResult = ();
    my @deleteResult = ();

    system("sync");
    stopwatch_start("write file");
        writeZeroes( "$dir/zero", 1024 * 1024 * 100 );
        system("sync");

    stopwatch_stop(\@writeResult);
   
    push( @results, [ $writeResult[0][0], 100.00 / ($writeResult[0][1] / 1000.00), 'MB/s' ] );
    unlink("$dir/zero");

    system("sync");
    system("cat $linuxgz > /dev/null");
    stopwatch_start("untar(93M/496M)");
        system("tar xzf $linuxgz -C $dir");
        system("sync");
    stopwatch_stop(\@results);

   
    #push ( @results, [ $untarResult[0][0], (93.00+495.00) / ($untarResult[0][1] / 1000.00), 'MB/s' ] );
    $du = qx(du -sm $dir | cut -f1);
    push( @results, [ 'du', $du, 'MB' ] );
    printf( "# disk space used: %d MB\n", $du );

    system("echo 3 > /proc/sys/vm/drop_caches");
    stopwatch_start("rsync");
        system("rsync -an $dir $dir/empty-rsync-target");
    stopwatch_stop(\@results);

    system("echo 3 > /proc/sys/vm/drop_caches");
    system("sync");
    
    #retrieve the total size of the working directory
    my $dirSizeDetail = `du -sk $dir`;
    $dirSizeDetail =~ /(\d+)/;
    my $dirSize = $1;

    stopwatch_start("rm");
        system("rm -Rf $dir/*");
        system("sync");
    stopwatch_stop(\@deleteResult);
    # delete speed in MB/s
    push ( @results, [ $deleteResult[0][0], ($dirSize / 1000.00) / ($deleteResult[0][1] / 1000.00), 'MB/s' ] );
   

    return \@results;
}

sub tabulate {
    my $r;

    $r = shift;
    my @encfs = @{$r};
    $r = shift;
    my @ecryptfs;
    if($r) {
        @ecryptfs = @{$r};
    }

    print " Test           | EncFS        | eCryptfs     | EncFS advantage\n";
    print ":---------------|-------------:|-------------:|---------------:\n";

    for ( my $i = 0 ; $i <= $#encfs ; $i++ ) {
        my $test = $encfs[$i][0];
        my $unit = $encfs[$i][2];

        my $en = $encfs[$i][1];
        my $ec = 0;
        my $ratio = 0;

        if( @ecryptfs ) {
            $ec = $ecryptfs[$i][1];
            $ratio = $ec / $en;
            if ( $unit =~ m!/s! ) {
                $ratio = $en / $ec;
            }
        }

        printf( "%-15s | %6d %-5s | %6d %-5s | %2.2f\n",
            $test, $en, $unit, $ec, $unit, $ratio );
    }
}

sub main {
    if ( $#ARGV < 0 ) {
        print "Usage: test/benchmark.pl DIR1 [DIR2] [...]\n";
        print "\n";
        print "Arguments:\n";
        print "  DIRn ... Working directory. This is where the encrypted files\n";
        print "           are stored. Specifying multiple directories will run\n";
        print "           the benchmark in each.\n";
        print "\n";
        print "For details about the testcases see PERFORMANCE.md.\n";

        exit(1);
    }

    my $centOs7 = 0;
    my $kernelRelease = `uname -r`;

    if ($kernelRelease =~ /.el7./){
      print "eCryptfs is not supported by CentOs 7\n";
      $centOs7 = 1;
    }  


    if ( $> != 0) {
        print("This test must be run as root!\n");
    }

    dl_linuxgz();
    my $workingDir;
    my $mountpoint;
    my $prefix;

    while ( $prefix = shift(@ARGV) ) {
        $workingDir = newWorkingDir($prefix);

        print "# mounting encfs\n";
        $mountpoint = mount_encfs($workingDir);
        my $encfs_results = benchmark($mountpoint);
	my $ecryptfs_results;
        	
        if ( $centOs7 == 0 ) {
        	print "# mounting ecryptfs\n";
        	$mountpoint = mount_ecryptfs($workingDir);
        	
		if($mountpoint) {
            	  $ecryptfs_results = benchmark($mountpoint);
        	}
	} else {
		print "# Skipping ecryptfs testing on CentOS 7 \n";

	}

        cleanup($workingDir);

        print "\nResults for $prefix\n";
        print "=============================================================\n\n";
        ( $centOs7 == 0) ? tabulate( $encfs_results, $ecryptfs_results ) : tabulate( $encfs_results);

        print "\n";
    }
}

main();
