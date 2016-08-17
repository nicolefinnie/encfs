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
    unlink("$dir");
    return(@writeResult);
}

# benchmark(directory, number_of_threads, size_in_MB);
sub benchmark {
    my $dir = shift;
    my $numberOfThreads = shift;
    my $sizeInMB = shift;

    my @threads = ();
    # 3-dimensional-array
    # number of threads -> ['name', delta_time, 'ms'], we only care about delta_time
    my @returnData = (); 
    my $totalThroughput = 0;
    my @totalTime = ();
    
    stopwatch_start("Total threads: ".$numberOfThreads);

    for (my $count=0 ; $count < $numberOfThreads; $count++) {
	my $filepath = $dir."/zero".$count;
    	my ($thr) = threads->create(\&subWriteZeroes, $count, $filepath, $sizeInMB*1024*1024);
	push(@threads, $thr);
    }

    foreach $thr (@threads){
	my @data = $thr->join();
    	push(@returnData, \@data);
    }
   
    stopwatch_stop(\@totalTime);

    for (my $count=0 ; $count < $numberOfThreads; $count++) {
        my $throughput = $sizeInMB / ($returnData[$count][0][1]/1000.00);
	$totalThroughput += $throughput;
    }

    # return average throughput, total time in ms
    return [($totalThroughput / $numberOfThreads ), $totalTime[0][1]];
}

sub main{
 	if ( $#ARGV < 0 ) {
        print "Usage: test/benchmark+multiWrite.pl DIR NumberOfThreads SizeOfFile \n";
        print "\n";
        print "Arguments:\n";
        print "  DIR ... Working directory. This is where the encrypted files\n";
        print "           are stored. Specifying multiple directories will run\n";
        print "           the benchmark in each.\n";
        print "\n";
   
        exit(1);

       
    }

    my $workingDir;
    my $mountpoint;
    my $prefix = shift(@ARGV);
    my $numberOfThreads = shift(@ARGV);
    my $sizeOfFile = shift(@ARGV);
    my @returnThroughputTotalTime = ();
    
    for (my $count=1; $count<=$numberOfThreads; $count++) {
        $workingDir = newWorkingDir($prefix);

        print "# mounting encfs\n";
        $mountpoint = mount_encfs($workingDir);
        push(@returnThroughputTotalTime, benchmark($mountpoint, $count, $sizeOfFile));
        cleanupEncfs($workingDir);
    }

    #TODO total time (s)   
    print "\nResults - Each thread writes a file of $sizeOfFile MB to $prefix\n";
    print "=============================================================\n\n";
    print " Number of threads   |  Throughput per thread  | Total disk write  | Total write time  |  Total throughput   |\n";
    print ":--------------------|------------------------:|------------------:|------------------:|--------------------:|\n";


     for (my $count=0; $count<$numberOfThreads; $count++) {
	my $throughputPerThread = $returnThroughputTotalTime[$count][0];
 	my $totalDiskWrite = ($sizeOfFile*($count+1));
	my $totalWriteTime = ($returnThroughputTotalTime[$count][1]/1000.0);
	my $totalThroughput = $totalDiskWrite * 1.0 / $totalWriteTime; 
    	printf( "%-20s | %12f %-10s | %8d %-8s | %12f %-4s | %12f %-6s |\n", " ".($count+1)." parallel write", $throughputPerThread, " MB/s", $totalDiskWrite, " MB", 
          $totalWriteTime," s", $totalThroughput, " MB/s");
     }
}



main();
