#!/usr/bin/perl

    use threads;
    use File::Temp;
    use warnings;

    require("tests/common.pl");

sub subWriteZeroes {

    my $threadTag = shift;
    my $dir = shift;
    my $size = shift;
    my @writeResult = ();
    system("sync");
    
    stopwatch_start("write thread ".$threadTag);
    writeZeroes( $dir, $size );
    system("sync");

    stopwatch_stop(\@writeResult);

    return(@writeResult);
}

sub benchmark {
    my $dir = shift;
   
    my $numberOfThreads = 24;
    my @threads = ();
    # 3-dimensional-array
    # number of threads -> ['name', delta_time, 'ms'], we only care about delta_time
    my @returnData = (); 
    my $sizeInMB = 100.00;

    for (my $count=0 ; $count < $numberOfThreads; $count++) {
	my $filepath = $dir."/zero".$count;
    	my ($thr) = threads->create(\&subWriteZeroes, $count, $filepath, $sizeInMB*1024*1024);
	push(@threads, $thr);
    }

    foreach $thr (@threads){
	my @data = $thr->join();
    	push(@returnData, \@data);
    }
   
    for (my $count=0 ; $count < $numberOfThreads; $count++) {
	print ($returnData[$count][0][0], ": ", $sizeInMB / ($returnData[$count][0][1]/1000.00), " MB/s \n");
    }

    return \@returnData;
}

sub main{
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

    my $workingDir;
    my $mountpoint;
    my $prefix;

    while ( $prefix = shift(@ARGV) ) {
        $workingDir = newWorkingDir($prefix);

        print "# mounting encfs\n";
        $mountpoint = mount_encfs($workingDir);
        my $encfs_results = benchmark($mountpoint);
        cleanupEncfs($workingDir);
	
        
    }

}



main();
