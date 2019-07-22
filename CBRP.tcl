set range 100

Phy/WirelessPhy set CPThresh_ 10.0
Phy/WirelessPhy set CSThresh_ 1.74269e-10   ;#400m
Phy/WirelessPhy set RXThresh_ 1.08918e-9    ;#160m
Phy/WirelessPhy set bandwidth_ 512kb
Phy/WirelessPhy set Pt_ [expr {0.281*$range}]

Mac/Simple set bandwidth_ 1Mb

set totalRounds 10
set lastEnergyUpdate 0
set transmissionEnergy 10
set receiveEnergy 5
set sleepEnergy 1
set idleEnergy 2
set maxSlot 4
set optionsCH {}
set final_CH {}
set selectedCH {}
set MESSAGE_PORT 42
set BROADCAST_ADDR -1

set x(0) 2
set xx(0) 3
set y(0) 1
set yy(0) 3

set num_nodes 140
#[expr $group_size * $num_groups]

set a($num_nodes)       0                          ;#Agents
set currEnergy($num_nodes) 1000                    ;
set val(initialEnergy)  1000                       ;
set val(threshEnergy)   10                          ;
set val(chan)           Channel/WirelessChannel    ;#Channel Type
set val(prop)           Propagation/TwoRayGround   ;# radio-propagation model
set val(netif)          Phy/WirelessPhy            ;# network interface type     


#set val(mac)            Mac/802_11                 ;# MAC type
#set val(mac)            Mac                 ;# MAC type
set val(mac)		Mac/Simple


set val(ifq)            Queue/DropTail/PriQueue    ;# interface queue type
set val(ll)             LL                         ;# link layer type
set val(ant)            Antenna/OmniAntenna        ;# antenna model
set val(ifqlen)         50                         ;# max packet in ifq

for {set i 0} {$i < $num_nodes} {incr i} {
   global n currEnergy ownerSchedule newSchedule  
   set currEnergy($i) 1000
   set ownerSchedule($i) {}
   set newSchedule($i) {}
}

# DumbAgent, AODV, and DSDV work.  DSR is broken
set val(rp) DumbAgent
#set val(rp)             DSDV
#set val(rp)             DSR
#set val(rp)		 AODV


# size of the topography
set val(x)             50
set val(y)             50 



set ns [new Simulator]

set f [open cbr.tr w]
$ns trace-all $f
set nf [open cbr.nam w]
$ns namtrace-all-wireless $nf $val(x) $val(y)

$ns use-newtrace

# set up topography object
set topo       [new Topography]

$topo load_flatgrid $val(x) $val(y)

#
# Create God
#
create-god $num_nodes


for {set i 0} {$i < $num_nodes} {incr i} {
    lappend optionsCH $i
    lappend final_CH $i
}

set chan_1_ [new $val(chan)]

$ns node-config -adhocRouting $val(rp) \
                -llType $val(ll) \
                -macType $val(mac) \
                -ifqType $val(ifq) \
                -ifqLen $val(ifqlen) \
                -antType $val(ant) \
                -propType $val(prop) \
                -phyType $val(netif) \
                -topoInstance $topo \
                -agentTrace ON \
                -routerTrace OFF \
                -macTrace ON \
                -movementTrace OFF \
                -channel $chan_1_ \
                -rxPower 35.28e-3 \
                -txPower 310.32e-3 \
                #-pt 0.00000000000000818 \ 
	      #  -idlePower 712e-6 \
	        -sleepPower 144e-9 

# subclass Agent/MessagePassing to make it do flooding

Class Agent/MessagePassing/Flooding -superclass Agent/MessagePassing

Agent/MessagePassing/Flooding instproc recv {source sport size data} {
    $self instvar messages_seen node_
    global n ns BROADCAST_ADDR optionsCH currEnergy receiveEnergy

    # extract message ID from message
    set message_id [lindex [split $data ":"] 0]
    puts "\nNode [$node_ node-addr] got message $message_id\n"
    
    set receiver [$node_ node-addr]
    set sender $message_id
    
    set currEnergy($receiver) [expr {$currEnergy($receiver) - $receiveEnergy}]
    set availableCH [lindex $optionsCH $receiver]
    set newCH [lappend availableCH $sender]
    lset optionsCH $receiver $newCH

    if {[lsearch $messages_seen $message_id] == -1} {
	lappend messages_seen $message_id
      #  $ns trace-annotate "[$node_ node-addr] received {$data} from $source"
      #  $ns trace-annotate "[$node_ node-addr] sending message $message_id"
	#$self sendto $size $data $BROADCAST_ADDR $sport
    } else {
        $ns trace-annotate "[$node_ node-addr] received redundant message $message_id from $source"
    }
}

Agent/MessagePassing/Flooding instproc send_message {size message_id data port} {
    $self instvar messages_seen node_
    global n ns MESSAGE_PORT BROADCAST_ADDR currEnergy range transmissionEnergy

    lappend messages_seen $message_id
    #$ns trace-annotate "[$node_ node-addr] sending message $message_id"
    set currEnergy($message_id) [expr {$currEnergy($message_id) - $transmissionEnergy}]
    $self sendto $size "$message_id:$data" $BROADCAST_ADDR $port
}


# create a bunch of nodes
for {set i 0} {$i < $num_nodes} {incr i} {
    global n x xx y yy

global n x y 
    set n($i) [$ns node]
    set x($i) [expr rand()*500]
    set y($i) [expr rand()*200]
    $n($i) set Y_ $x($i)
    $n($i) set X_ $y($i)
    $n($i) set Z_ 0.0
    $n($i) color red
    $ns initial_node_pos $n($i) 20
    
    set xx($i) [expr rand()*$val(x)]
    set yy($i) [expr rand()*$val(y)]
    
    $ns at 0.0 "$n($i) setdest $xx($i) $yy($i) 1500.0"
}

# attach a new Agent/MessagePassing/Flooding to each node on port $MESSAGE_PORT
for {set i 0} {$i < $num_nodes} {incr i} {
    global n a 
    set a($i) [new Agent/MessagePassing/Flooding]
    $n($i) attach  $a($i) $MESSAGE_PORT
    $a($i) set messages_seen {}
}

set sink [$ns node]
set sinkAgent [new Agent/Null]
$ns attach-agent $sink $sinkAgent
set sinkX 25
set sinkY 25
set sinkID $num_nodes

set r 20

$ns at 0.010  "selectCH"

proc record {} {
        global f0 f1 ns round
        set f0 [open out0.tr a]
        set f1 [open out1.tr a]
        puts [totalEnergy]
        puts [$ns now]
        puts $f0 "$round [totalEnergy]"
        puts $f1 "$round [totalAlive]"
        close $f0
        close $f1
        $ns at [expr [$ns now] + 0.0001] "selectCH"
}

proc totalEnergy {} {
   global currEnergy num_nodes
   set sum 0
   for {set i 0} {$i < $num_nodes} {incr i} {
     if {$currEnergy($i)>0} {
       set sum [expr {$sum + $currEnergy($i)}]
     } 
   }
   return $sum
}

proc totalAlive {} {
   global currEnergy num_nodes
   set sum 0
   for {set i 0} {$i < $num_nodes} {incr i} {
     if {$currEnergy($i)>=10} {
       set sum [expr {$sum + 1}]
     } 
   }
   return $sum
}
set round 0
proc selectCH {} {
   global n num_nodes val currEnergy selectedCH round totalRounds ns f nf val f0 f1 f2 out0.tr
   set count 0
   set round [expr {$round+1}]
   if {$round > $totalRounds} {    
        $ns flush-trace
        close $f
        close $nf
#       exec xgraph out1.tr
        exec xgraph out0.tr
#       puts "running nam..."
#       exec nam cbr.nam &
        exit 0
   }

   for {set i 0} {$i < $num_nodes} {incr i} {
      if {$currEnergy($i) >= $val(threshEnergy)} {
         set count [expr {$count+1}]
      }
   }
   set count [expr {$count/10}]
   for {set i 0} {$i < $num_nodes} {incr i} {        
    if {$currEnergy($i) >= $val(threshEnergy)} {
       lappend selectedCH $i
       set count [expr {$count-1}]
    }
    if {$count <= 0} {
       break;
    }
   }

   $ns at [expr [$ns now] + 0.0001] "broadcast"
}

proc broadcast {} {
   global n num_nodes selectedCH a MESSAGE_PORT ns
   foreach ch $selectedCH {
      $a($ch) send_message 200 $ch {first message}  $MESSAGE_PORT
   }

   $ns at [expr [$ns now] + 0.0001] "xyz"
}
proc xyz {} {
   global n optionsCH ns final_CH num_nodes selectedCH x xx y yy n currEnergy val
   puts "FINAL CH"
   puts $optionsCH
   set h 0
   for {set i 0} {$i <$num_nodes} {incr i} {
      if {$currEnergy($i) < $val(threshEnergy)} { continue; }
      set b [lsearch $selectedCH $i]
      if {$b!=-1} { } else {
         set availableCH [lindex $optionsCH $i]
         set k 1
         set min 3000
         foreach ch $availableCH {
            if {$k==1} {} else {
               set d1 ($xx($i)-$x($i))*($xx($i)-$x($i))+($yy($i)-$y($i))*($yy($i)-$y($i))
               set dx1 $xx($i)-$x($i)
               set dy1 $yy($i)-$y($i)
               set constx $dx1/sqrt($d1)
               set consty $dy1/sqrt($d1)
               set now [$ns now]
               set d2 1500*$now
               set fx $constx*$d2
               set fy $consty*$d2
               set d1 ($xx($ch)-$x($ch))*($xx($ch)-$x($ch))+($yy($ch)-$y($ch))*($yy($ch)-$y($ch))
               set dx1 $xx($ch)-$x($ch)
               set dy1 $yy($ch)-$y($ch)
               set constx $dx1/sqrt($d1)
               set consty $dy1/sqrt($d1)
               set now [$ns now]
               set d2 1500*$now
               set cx $constx*$d2
               set cy $consty*$d2
               set f ($cx-$fx)*($cx-$fx)+($cy-$fy)*($cy-$fy)
               if {$min > $f} {   
                  set min $d1-$d2
                  lset final_CH $i $ch
               }     
            }
            set k $k+1
         }
      }
   }
   puts "SELECTED CH"
   puts $final_CH
   puts [llength $final_CH]
   set i 0
   foreach value $final_CH {
      if {$value == 1} {
      #   $n($i) color "#FF0000"
      }
      if {$value == 12} {
     #    $n($i) color orange
      }
      if {$value == 22} {
    #     $n($i) color blue
      } 
      set i $i+1             
   }
   $ns at [expr [$ns now] + 0.0001] "sendSchedule"
}

proc sendSchedule {} {
   global n ns selectedCH num_nodes final_CH maxSlot a MESSAGE_PORT newSchedule ownerSchedule currEnergy val lastEnergyUpdate
   foreach ch $selectedCH {
      set newSchedule($ch) {}
      set ownerSchedule($ch) {}
      for {set i 0} {$i <$num_nodes} {incr i} {
         if {$currEnergy($i) < $val(threshEnergy)} { continue; }
         if {[lindex $final_CH $i] == $ch} {
             lappend newSchedule($ch) $i
         }
      }
      set ownerSchedule($ch) [lowner $newSchedule($ch) $maxSlot]
      set newSchedule($ch) [lshift $newSchedule($ch) $maxSlot]
      puts "Sched"
      puts $newSchedule($ch)
      puts $ownerSchedule($ch)
      puts "combined Sched"
      set x {}
      lappend x $newSchedule($ch)
      lappend x $ownerSchedule($ch)
      puts $x
      puts "broadcast"
      puts $a($ch)
      puts $ch
      $a($ch) send_message 200 $ch $x  $MESSAGE_PORT
   }
   set lastEnergyUpdate [$ns now]
   $ns at [expr [$ns now] + 0.0001] "forward"
}

proc lowner {listV x} {
   global n selectedCH num_nodes final_CH
    set list {}
    set count -1
    foreach ch $listV {
       set count [expr {$count+1}]
       if {$count >= $x} {break;}
       lappend list $ch
     #  if {$count + 1 == [llength $final_CH]} {break;}      
    }
    return $list
}
proc lshift {listVar x} {
    global n selectedCH num_nodes final_CH
    set list {}
    set count [expr {$x - 1}]
    foreach ch $listVar {
       set count [expr {$count+1}]
       if {$count >= [llength $listVar]} {break;}
       lappend list [lindex $listVar $count]
     #  if {$count + 1 == [llength $final_CH]} {break;}      
    }
    return $list
}

proc forward {} {
   global n ns newSchedule ownerSchedule selectedCH num_nodes final_CH currEnergy x y val
   set node_range 10
   foreach ch $selectedCH {
     foreach i $ownerSchedule($ch) {
        if {[llength $i] == 0} {continue;}
        set dist [expr {($x($i)-$x($ch))*($x($i)-$x($ch)) + ($y($i)-$y($ch))*($y($i)-$y($ch))}]
        if {$dist > $node_range} {
           if {[llength $newSchedule($ch)] == 0} {continue;}
           set i [lindex $newSchedule($ch) 0]
           set newSchedule($ch) [lshift $newSchedule($ch) 1]
        }
        set dist [expr {($x($i)-$x($ch))*($x($i)-$x($ch)) + ($y($i)-$y($ch))*($y($i)-$y($ch))}]
        if {$dist > $node_range} {
           continue;
        }
        set proxy [transmit $i $ch]
     }  
   }
   for {set it 0} {$it <$num_nodes} {incr it} {
      if {$currEnergy($it) < 10} { continue; }
      set xz [lindex $final_CH $it]
      set b [lsearch $selectedCH $xz]
      if {$b == -1} {set proxy [transmit $i $num_nodes]}
   }
   
   foreach ch $selectedCH {
      set proxy [transmit $ch $num_nodes]
   }
   $ns at [expr [$ns now] + 0.0001] "energy"
}

proc transmit {a1 b1} {
global n a sinkAgent ns num_nodes currEnergy transmissionEnergy
#set udp0 [new Agent/UDP]
#$ns attach-agent $n($a1) $udp0

# Create a CBR traffic source and attach it to udp0
set cbr0 [new Application/Traffic/CBR]
$cbr0 set packetSize_ 500
$cbr0 set interval_ 0.005
$cbr0 attach-agent $a($a1)

if {$b1 == $num_nodes} {
$ns connect $a($a1) $sinkAgent
} else {
$ns connect $a($a1) $a($b1)
}
$ns at [$ns now] "$cbr0 start"
$ns at [$ns now] "$cbr0 stop"

set currEnergy($a1) [expr {$currEnergy($a1) - $transmissionEnergy}]
return 0
}

proc energy {} {
    global n lastEnergyUpdate ns ownerSchedule selectedCH num_nodes currEnergy idleEnergy sleepEnergy
    set duration [expr {[$ns now] - $lastEnergyUpdate}]  
    for {set it 0} {$it <$num_nodes} {incr it} {
      if {$currEnergy($it)< 10} { continue; }
      set currEnergy($it) [expr {$currEnergy($it) - $duration * $idleEnergy} ]
   }
    foreach ch $selectedCH {
     foreach i $ownerSchedule($ch) {
        set currEnergy($i) [expr {$currEnergy($i) + $duration * $idleEnergy - $duration * $sleepEnergy}] 
     }  
   }
   set lastEnergyUpdate [$ns now]
   $ns at [expr [$ns now] + 0.0001] "record"
}


$ns run
