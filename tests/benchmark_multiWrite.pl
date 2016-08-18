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
    my $prefixNative = shift(@ARGV);
    my $numberOfThreads = shift(@ARGV);
    my $sizeOfFile = shift(@ARGV);
    my @returnThroughputTotalTime = ();
    my @nativeReturnThroughputTotalTime = ();
   

    print "Test write disk speed with encryption.........\n";    
    for (my $count=1; $count<=$numberOfThreads; $count++) {
        $workingDir = newWorkingDir($prefix);

        #print "# mounting encfs".$workingDir."\n";
        #$mountpoint = mount_encfs($workingDir);
	
 	#print "# mounting eCryptfs\n";
        #$mountpoint = mount_ecryptfs($workingDir);
        push(@returnThroughputTotalTime, benchmark($workingDir, $count, $sizeOfFile));
 	
        print "done\n";
	cleanupLuks($workingDir);
	#cleanupEcryptfs($workingDir);
    }


    print "Test write disk speed without encryption.........\n";    
    for (my $count=1; $count<=$numberOfThreads; $count++) {
        $workingDir = newWorkingDir($prefixNative);
	
        push(@nativeReturnThroughputTotalTime, benchmark($workingDir, $count, $sizeOfFile));
        print "done\n";
	cleanupLuks($workingDir);
	#cleanupEcryptfs($workingDir);
    }


    #TODO total time (s)   
    print "\nResults - Each thread writes a file of $sizeOfFile MB to $prefix\n";
    print "=============================================================\n\n";
    print " Number of threads | Throughput per thread | Total write  |  Total time  | Total throughput | Ratio to native |\n";
    print ":------------------|----------------------:|-------------:|-------------:|-----------------:|----------------:|\n";


     for (my $count=0; $count<$numberOfThreads; $count++) {
	my $throughputPerThread = $returnThroughputTotalTime[$count][0];
	my $nativeThroughputPerThread = $nativeReturnThroughputTotalTime[$count][0];
	#print "native throughput:".$nativeThroughputPerThread;
 	my $totalDiskWrite = ($sizeOfFile*($count+1));
	my $totalWriteTime = ($returnThroughputTotalTime[$count][1]/1000.0);
	my $totalThroughput = $totalDiskWrite * 1.0 / $totalWriteTime; 

	my $ratioToNative = $throughputPerThread / 1.0 / $nativeThroughputPerThread;
    	printf( "%-18s | %10.2f %-10s | %6d %-5s | %8.4f %-3s | %8.2f %-7s | %15.2f |\n", " ".($count+1)." parallel write", $throughputPerThread, " MB/s", $totalDiskWrite, " MB", 
          $totalWriteTime," s", $totalThroughput, " MB/s", $ratioToNative );
     }
}



main();
