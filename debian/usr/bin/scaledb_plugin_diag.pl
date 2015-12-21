#!/usr/bin/env perl

#
# $Id: scaledb_plugin_diag.pl,v 1.1 2015-12-18 00:18:18 igor Exp $
#

#
# to analyze MySQL configuration with respect to file system layout,
#  network and memory
#

use strict;
use warnings;
use Getopt::Long;

my $ERRORS =0;
my %mysql_config=();
my %config =();
my $my_cnf=undef;
my $verbose=undef;
my $help   =undef;
my $plugin_cnf=undef;
my $mysqld =  undef;

my $ts = time;
my $temp_dir=defined $ENV{TEMP}?$ENV{TEMP}:"/tmp";
my $output_file = "$temp_dir/$ENV{USER}.plugin_info.$ts.txt";

sub help {
    print "Usage: --config=<mysql_config> [options]\n";
    print "       options:\n";
    print "               --help       : prints this message and exit\n";
    print "               --verbose    : prints messages about what it does\n";
    print "               --mysqld=<binary>: location of mysqld (default:none)\n";
    print "               -o filename  : stores diagnostics into file (default : \$TEMP/\$USER.cas_info.txt\n";
    exit 1;
}

sub info {
    my $message = shift;
    my ($Y,$M,$D,$h,$m,$s) = (localtime())[5,4,3,2,1,0];
    $Y+=1900;
    $M+=1;
    my $formated_message=sprintf("%d-%02d-%02d %02d:%02d.%02d INFO %s\n",$Y,$M,$D,$h,$m,$s,$message);

    # always print to output file for diagnostics
    print FINFO $formated_message;

    # but only print to STDOUT when user set $verbose flag
    return unless $verbose ;
    print $formated_message;
}

sub info2 {
    my $message = shift;
    my ($Y,$M,$D,$h,$m,$s) = (localtime())[5,4,3,2,1,0];
    $Y+=1900;
    $M+=1;
    my $formated_message=sprintf("%d-%02d-%02d %02d:%02d.%02d INFO %s\n",$Y,$M,$D,$h,$m,$s,$message);
    print FINFO $formated_message;
}

sub error_exit {
    my $message = shift;
    my ($Y,$M,$D,$h,$m,$s) = (localtime())[5,4,3,2,1,0];
    $Y+=1900;
    $M+=1;
    my $formated_message = sprintf("%d-%02d-%02d %02d:%02d.%02d FATAL %s\n",$Y,$M,$D,$h,$m,$s,$message);
    $ERRORS=1 if($ERRORS==0);
    print FINFO $formated_message;
    print $formated_message;

    print FINFO "Total errors: $ERRORS\n";
    print "Total errors: $ERRORS\n";

    close FINFO;

    print "Results of this run saved in '$output_file'";
    exit 1;
}

sub error {
    $ERRORS++;
    my $message = shift;
    my ($Y,$M,$D,$h,$m,$s) = (localtime())[5,4,3,2,1,0];
    $Y+=1900;
    $M+=1;
    my $formated_message = sprintf("%d-%02d-%02d %02d:%02d.%02d ERROR %s\n",$Y,$M,$D,$h,$m,$s,$message);
    print FINFO $formated_message;
    print $formated_message;
}

sub check_must_haves{
    my $sub = "check_must_haves";
    info2 "$sub - entered";
    my @must_haves = qw(scaledb_cas_config_ips scaledb_cas_config_ports );
    foreach my $param(@must_haves){
            info "$sub - verifying config param '$param' exists";
            if(!exists $config{$param}){
                error "$sub - missing config parameter:'$param'";
                info2 "$sub - dumping configs:";
                map{info2 "    '$_'='$config{$_}'\n"} (keys %config);
                error_exit "$sub - can't continue without '$param'";
            }
    }

    info "$sub - checking for transaction-isolation=READ-COMMITTED";
    if(! exists $mysql_config{transaction_isolation} 
        or $mysql_config{transaction_isolation} ne lc'READ-COMMITTED') {
        error "$sub - mysql configuration missing or incorrect,".
              " should have: transaction-isolation=READ-COMMITTED";
    }

    info "$sub - checking for query_cache_size=0";
    if(! exists $mysql_config{query_cache_size} 
        or $mysql_config{query_cache_size} ne '0') {
        error "$sub - mysql configuration missing or incorrect,".
              " should have: query_cache_size=0";
    }

    info2 "$sub - exited";
}

#
# returns true if param is know
# false otherwise
#
sub check_known_params{
    my $sub = "check_known_params";
    my $new_param = shift;
    info2 "$sub - received param '$new_param'";
    my %list_of_params = (
    "scaledb_data_directory"=>1,
    "scaledb_log_directory"=>1,
    "scaledb_max_file_handles"=>1,
    "scaledb_aio_flag"=>1,
    "scaledb_io_threads"=>1,
    "scaledb_cas_config_ips"=>1,
    "scaledb_cas_config_ports"=>1,
    "scaledb_slm_threads"=>1,
    "scaledb_buffer_size_index"=>1,
    "scaledb_buffer_size_data"=>1,
    "scaledb_buffer_size_blob"=>1,
    "scaledb_cluster_password"=>1,
    "scaledb_debug"=>2,
    "scaledb_debug_interactive"=>2,
    "scaledb_debug_buffer_size"=>2,
    "scaledb_debug_file"=>1,
    "scaledb_debug_lines_per_file"=>1,
    "scaledb_debug_files_count"=>1,
    "scaledb_debug_string"=>2,
    "scaledb_debug_locking_mode"=>2,
    "scaledb_log_sql"=>3,
    "scaledb_node_name"=>2,
    "scaledb_service_port"=>2,
    "scaledb_cluster_port"=>1,
    "scaledb_cluster_user"=>1,
    );

   if(!exists $list_of_params{$new_param}){
     error "$sub - parameter:'$new_param' is unknown" ;
     return 0;
    }
     
    info "$sub - verified '$new_param' - ok";
    info2 "$sub - exited";
    return 1;
}

#
# From Mb to Kb
#
sub calc_scaledb_memory {
    my $sub = "calc_scaledb_memory";
    info2 "$sub - entered";
    my $ret_code=3;

    #
    #  when buffers specified in 8Kblocks
    #
    foreach my $component ( qw(index data blob)){

       if(!exists $config{"scaledb_buffer_size_$component"}){
            info "$sub - cache for $component is not specified";     
            $config{"scaledb_buffer_size_$component"}=0;
            $ret_code--;
            next;
       }

       info2 "$sub - cache configuration for $component: ".
             $config{"scaledb_buffer_size_$component"};

       if($config{"scaledb_buffer_size_$component"}=~/^(\d+)$/){
            info2 "$sub - cache for '$component' configured in 8K blocks!";
            $config{"scaledb_buffer_size_$component"}=$1*8;
        } 
    }

    #
    # exiting because cache sizes are not specified
    #
    return undef unless $ret_code;

    #
    # when buffers specified in Mb
    #
    foreach my $component ( qw(index data blob)){
       if($config{"scaledb_buffer_size_$component"}=~/^(\d+)\s*M$/){
            $config{"scaledb_buffer_size_$component"}=$1*1024;
        } 

        if($config{"scaledb_buffer_size_$component"}!~/^(\d+)$/){
            error "$sub - invalid value '$1' for $component cache configuration";
            next;
        }

        info "$sub - converted cache size for $component to (Kb) ".
             $config{"scaledb_buffer_size_$component"};
    }

    info2 "$sub - exited";
}


#
# From Mb to Kb
# - POST -  mysql_config{total_required_memory}
#
sub calc_mysql_memory {
    my $sub = "calc_mysql_memory";
    info2 "$sub - entered";
    my $ret_code=3;
    $mysql_config{total_required_memory}=0;

    my @list_of_buffers = qw(
key_buffer_size
read_rnd_buffer_size
sort_buffer_size
myisam_sort_buffer_size
);

    my @list_of_innodb_buffers = qw(
innodb_additional_mem_pool_size
innodb_log_file_size
innodb_buffer_pool_size
);

    my @all_buffers;
    if(exists $mysql_config{skip_innodb} 
            or ( exists $mysql_config{skip_innodb} and  $mysql_config{skip_innodb} == '1' )){
        info2 "$sub - innodb disabled - not couting innodb buffers";
        @all_buffers = @list_of_buffers;
    }else{
        info2 "$sub - including innodb buffers";
        @all_buffers = (@list_of_buffers,@list_of_innodb_buffers);
    }

    #
    #  when buffers specified in 8Kblocks
    #
    foreach my $param( @all_buffers ){

       if(!exists $mysql_config{$param}){
            info2 "$sub - buffer $param is not set";
            next;
       }

       info2 "$sub - buffer $param set to:$mysql_config{$param}";

       if($mysql_config{$param}=~/^(\d+)$/){
            info2 "$sub - buffer $param configured in bytes,converting to kb";
            $mysql_config{$param}=$1/1024;
        }elsif($mysql_config{$param}=~/^(\d+)\s*(.)$/){ 
            if(lc $2 eq 'm'){
                info2 "$sub - buffer $param configured in M-bytes,converting to kb";
                $mysql_config{$param}=$1*1024;
            }elsif(lc $2 eq 'k'){
                info2 "$sub - buffer $param configured in K-bytes,don't convert";
            }elsif(lc $2 eq 'g'){
                info2 "$sub - buffer $param configured in G-bytes,converting to kb";
                $mysql_config{$param}=$1*1024*1024;
            }else{
                error "$sub - buffer $param configured with unsupported units,converting to kb";
                $mysql_config{$param}=$1*1024;
            }
            
        }else{
                error "$sub - cant' understand configuration for $param,settig to 0";
                $mysql_config{$param}=0;
        }
        $mysql_config{total_required_memory}+=$mysql_config{$param};
        
    }
    info2 "$sub - mysql requires (Kb):$mysql_config{total_required_memory}";
    info2 "$sub - exited";
}

sub evaluate_memory {
    my $sub = "evaluate_memory"; 
    info2 "$sub - entered";
    my %meminfo = ();
    open MEMINFO,"/proc/meminfo"
        or error_exit "main - failed to open /proc/meminfo:$!";
    while(<MEMINFO>){
        chomp;
        if (/^(\w+):\s*(\d+)\b/){
            info2 "main - meminfo:'$1'='$2'";
            $meminfo{$1}=$2; 
        }
    }
    close MEMINFO;
    
    my $available_memory = $meminfo{MemFree}+$meminfo{Cached};
    my $user_requested_memory = $config{scaledb_buffer_size_index} +
                            $config{scaledb_buffer_size_data} +
                            $config{scaledb_buffer_size_blob} +
                            $mysql_config{total_required_memory};
    
    info "$sub - comparing available_memory(KB):'$available_memory' to needed '$user_requested_memory'";
    
    my $diff = 100*$user_requested_memory/$available_memory;
    info2 "$sub - calculated prcntl diff: $diff ";
    
    if ($user_requested_memory>$available_memory){
        error "$sub - requested too much memory for mysql!";
    }elsif ($diff > 80 ){ 
        error "$sub - mysql maybe configured for too much memory !"; 
    }else{
        info "$sub - memory allocation for mysql looks ok";
    }
    
    info2 "$sub - exited";
}




sub parsing_mysql_conifg {
    my $sub = "parsing_mysql_config";
    info2 "$sub - entered";
 
    if ( ! -r $my_cnf ){
        error_exit "$sub - $my_cnf does not exist or is not readable"; 
    }

    open FMYCNF,"$my_cnf"
        or error_exit "$sub - failed to open configuration $my_cnf:$!\n";
    
    info "$sub - reading configuration from '$my_cnf'";
    my $started_mysqld_section=undef; 
    my $mysqld_section_found=undef;
    while(<FMYCNF>){
        next if /^#/;
        chomp;
        info2 "$sub - reading mysql config:$_";

        last if($started_mysqld_section and /^\[/);
        $started_mysqld_section=1 if(/^\[\s*mysqld\s*\]/);
        next unless $started_mysqld_section;
        $mysqld_section_found=1;

        if(/\s*(.*?)\s*=\s*(.*?)\s*$/){
            my $param=lc $1;
            my $value=lc $2;
            info2 "$sub - got mysql config param :'$param'='$value'";
            $value=~s/("|')//g;
            $param=~s/-/_/g;
            $value=1 if $value eq 'true';
            $value=0 if $value eq 'false';
            if(exists $mysql_config{$param}){
                error "$sub - param '$param' reassigning from '$mysql_config{$param}' to '$mysql_config{$param}'";
            }
            $mysql_config{$param}=$value;
        }
    }
    close FMYCNF;
   
    error_exit "failed to find [mysqld] ".
               " section in mysql configuration file" unless $mysqld_section_found; 

    $mysql_config{port}=3306 unless exists $mysql_config{port};  
    info2 "$sub - exited";
}

sub find_plugin_config {
    my $sub = "find_plugin_config";
    info2 "$sub - entered";

    info2 "$sub - determining absolute path for plugin config";
    if(exists $mysql_config{scaledb_config_file}){
       $plugin_cnf = $mysql_config{scaledb_config_file};
    }else{
       if(exists $mysql_config{datadir}){
            $mysql_config{datadir}=~s/\/$//;
            $plugin_cnf = $mysql_config{datadir}."/scaledb.cnf";
        }elsif($mysqld){
            my $mysqld_help = `$mysqld --help --verbose`;
            if($?){
                error "$sub - Failed to find plugin configuration";
                error_exit "$sub - Failed to start mysqld to get default datadir";
            }
        }else{
             error_exit "$sub - Failed to find plugin configuration\n".
                        " provide '--mysqld=mysqld_binary_location'\n".
                        " to get default datadir";
                 
        }
    }
    info "$sub - found plugin configuration:'$plugin_cnf'";
    error_exit "$sub - There is no such file :'$plugin_cnf',".
               " or it is not readable" unless -r $plugin_cnf;

    info2 "$sub - exited";
}

sub parsing_plugin_config {
    my $sub = "parsing_plugin_config";
    info2 "$sub - entered";

    open FCNF,"$plugin_cnf"
        or error_exit "$sub - failed to open configuration $plugin_cnf:$!\n";
    
    info "$sub - reading configuration from '$plugin_cnf'";
    
    while(<FCNF>){
        next if /^#/;
        chomp;
        if(/\s*(.*?)\s*=\s*(.*?)\s*$/){
            my $param=$1;
            my $value=$2;
            info2 "$sub - got plugin config param :'$param'='$value'";
            next unless check_known_params($param);
            $value=~s/("|')//g;
            if(exists $config{$param}){
                error "$sub - param '$param' reassigning from '$config{$param}' to '$config{$param}'";
            }
            $config{$param}=$value;
        }
    }
    close FCNF;
     
    info2 "$sub - exited";
}

sub verify_plugin_location {
    my $sub = "verify_plugin_location";
    info2 "$sub - entered";
    if(exists $mysql_config{plugin_dir}){
        my $scaledb_plugin = "$mysql_config{plugin_dir}/ha_scaledb.so";
        error "$sub - failed to find $scaledb_plugin" unless -f $scaledb_plugin;
    }

    my @libscaledb=();
    if(exists $ENV{LD_LIBRARY_PATH}){
        foreach my $dir (split /:/,$ENV{LD_LIBRARY_PATH}){
                $dir=~s/\/$//;
               if( -x "$dir/libscaledb.so" ){
                      push @libscaledb,"$dir/libscaledb.so";
                }
        }
    }
    foreach my $dir (qw(/lib64 /usr/lib64 /usr/local/lib64)){
               if( -x "$dir/libscaledb.so" ){
                      push @libscaledb,"$dir/libscaledb.so";
                }
    }
    if(@libscaledb==1){
        info "$sub - found libscaledb: $libscaledb[0]";
    }elsif(@libscaledb==0){
        error"$sub - did not find libscaledb, specify in LD_LIBRARY_PATH";
    }else{
        error "$sub - found many instances of libscaledb library:@libscaledb";
    }
    
    info2 "$sub - exited";
}

#
#
# MAIN
#
#
GetOptions("config=s"=>\$my_cnf,
        "help"=>\$help,
        "verbose"=>\$verbose,
        "mysqld=s"=>\$mysqld,
        "o=s"=>\$output_file);

help() unless $my_cnf;
help() if $help;

open FINFO,">$output_file" 
    or die "Failed openning output file for diagnostic messages:$output_file:$!\n";

info2 "main - dumping diagnositcs to '$output_file'";

parsing_mysql_conifg();
find_plugin_config();
parsing_plugin_config();
check_must_haves();
verify_plugin_location();

my @cas_ips;
my @cas_ports;
info "main - extracting cas configuration ip and port";
@cas_ips   = split /,/,$config{scaledb_cas_config_ips};
@cas_ports = split /,/,$config{scaledb_cas_config_ports};

if (@cas_ips==1){
  info "main - configured without mirror!";
}elsif (@cas_ips==2){
  info "main - configured for a mirror";
}else{
  error "main - to many configuration ips - support only for 1 mirror";
}


my $cas_ip   = $cas_ips[0];
my $cas_port = $cas_ports[0];
$cas_ip=~s/\s*//g;
$cas_port=~s/\s*//g;

#
# bad formating 
# 
error_exit "main - bad ip address:$cas_ip" if $cas_ip!~/^\d+\.\d+\.\d+\.\d+$/;
error_exit "main - bad port :$cas_port"    if $cas_port!~/^\d+$/;

#
# CAS_PORT should be in allowable range and available
#
error "main - cas_port:$cas_port is not in ".
      "permissisble range:(1000 to 56000)" 
      if $cas_port<1000 or $cas_port>56000;


info "main - trying to ping '$cas_ip:$cas_port'";

#
# TESTING THAT IP ADDRESS AVAILABLE
#
info2 "main - searching for netcat binary";
my $netcat=`which nc 2>/dev/null`;
if (!defined $netcat){
    info2 "didn't find netcat in PATH, looking in other places";
  foreach my $dir (qw(/sbin /usr/sbin /usr/local/sbin)){
     $netcat="$dir/nc" if -f "$dir/nc";
  }
}

if($netcat){
    chomp $netcat;
    info "main - found netcat: '$netcat'";
    my $cmd = "echo PING | $netcat $cas_ip $cas_port";
    info "main - running:'$cmd'";
    my @nc_output=`$cmd 2>&1`;
    if($?){
           error "main - netcat failed to connect to cas" ;
    }elsif( $nc_output[0]!~/PONG/){
      error "main - test failed for $cas_ip:$cas_port" 
    }else{
      info "main - $cas_ip:$cas_port test - ok" 
    }
}else{
    error "failed to find netcat, continue without".
          " testing for CAS availability" unless $netcat;
}

#
# network testing
#
my @listeners=();
info "main - searching for netstat binary in PATH";
my $netstat = `which netstat 2>/dev/null`;
error_exit "main - failed to find netstat" if($?);
chomp $netstat;

$netstat = "$netstat -t -n -p -l -T ";
info "main - runnning '$netstat' to determine running TCP servers";

my @ntout = `$netstat 2>&1`;
error "main - failed to run netstat:@ntout" if ($?);

foreach my $line (@ntout){
    next unless $line=~/^tcp/;
    my $server = (split/\s+/,$line)[3];

    my ($server_ip,$server_port) = split/:/,$server;
    if( $server_port eq $mysql_config{port}){
        error "main - port $mysql_config{port} is not available - it is already in use";
    }
}

#
# got overal scaledb 
#
calc_scaledb_memory();
calc_mysql_memory();
evaluate_memory();

#
# our information collected
#
close FINFO;
print "Results of this run saved in '$output_file'\n";

