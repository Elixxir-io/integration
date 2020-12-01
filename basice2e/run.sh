#!/bin/bash

# NOTE: This is verbose on purpose.

set -e

rm -fr results || true
rm -fr blob* || true
rm *-contact.json || true
rm server-5.qdstrm || true
rm server-5.qdrep || true

mkdir -p .elixxir

#export GRPC_GO_LOG_VERBOSITY_LEVEL=99
#export GRPC_GO_LOG_SEVERITY_LEVEL=info

SERVERLOGS=results/servers
GATEWAYLOGS=results/gateways
CLIENTOUT=results/clients
DUMMYOUT=results/dummy-console.txt
UDBOUT=results/udb-console.txt
CLIENTCLEAN=results/clients-cleaned

CLIENTOPTS="--password hello --ndf ndf.json --unsafe-channel-creation --verbose"

mkdir -p $SERVERLOGS
mkdir -p $GATEWAYLOGS
mkdir -p $CLIENTOUT
mkdir -p $CLIENTCLEAN

echo "STARTING SERVERS..."

PERMCMD="../bin/permissioning --logLevel 2 -c permissioning.yaml "
$PERMCMD > results/permissioning-console.txt 2>&1 &
PIDVAL=$!
echo "$PERMCMD -- $PIDVAL"

for SERVERID in $(seq 5 -1 1)
do
    IDX=$(($SERVERID - 1))
    SERVERCMD="../bin/server --config server-$SERVERID.yaml"
    if [ $SERVERID -eq 5 ] && [ -n "$NSYSENABLED" ]
    then
        SERVERCMD="nsys profile --session-new=gputest --trace=cuda -o server-$SERVERID $SERVERCMD"
    fi
    $SERVERCMD > $SERVERLOGS/server-$SERVERID-console.txt 2>&1 &
    PIDVAL=$!
    echo "$SERVERCMD -- $PIDVAL"
done

# Start gateways
for GWID in $(seq 5 -1 1)
do
    IDX=$(($GWID - 1))
    GATEWAYCMD="../bin/gateway --logLevel 2 --config gateway-$GWID.yaml"
    $GATEWAYCMD > $GATEWAYLOGS/gateway-$GWID-console.txt 2>&1 &
    PIDVAL=$!
    echo "$GATEWAYCMD -- $PIDVAL"
done

jobs -p > results/serverpids

finish() {
    echo "STOPPING SERVERS AND GATEWAYS..."
    if [ -n "$NSYSENABLED" ]
    then
        nsys stop --session=gputest
    fi
    # NOTE: jobs -p doesn't work in a signal handler
    for job in $(cat results/serverpids)
    do
        echo "KILLING $job"
        kill $job || true
    done

    sleep 5

    for job in $(cat results/serverpids)
    do
        echo "KILL -9 $job"
        kill -9 $job || true
    done
    #tail $SERVERLOGS/*
    #tail $CLIENTCLEAN/*
    #diff -ruN clients.goldoutput $CLIENTCLEAN
}

trap finish EXIT
trap finish INT

# Sleeps can die in a fire on the sun, we wait for the servers to start running
# rounds
rm rid.txt || true
touch rid.txt
cnt=0
echo -n "Waiting for a round to run"
while [ ! -s rid.txt ] && [ $cnt -lt 120 ]; do
    sleep 1
    grep -a "RID 1 ReceiveFinishRealtime END" results/servers/server-5.log > rid.txt || true
    cnt=$(($cnt + 1))
    echo -n "."
done

echo "DONE LETS DO STUFF"

# Start a user discovery bot server
# echo "STARTING UDB..."
# UDBCMD="../bin/udb --logLevel 3 --config udb.yaml -l 1"
# $UDBCMD >> $UDBOUT 2>&1 &
# PIDVAL=$!
# echo $PIDVAL >> results/serverpids
# echo "$UDBCMD -- $PIDVAL"

# rm rid.txt || true
# while [ ! -s rid.txt ] && [ $cnt -lt 30 ]; do
#     sleep 1
#     grep -a "Gateway Polling for Message Reception Begun" results/udb-console.txt > rid.txt || true
#     cnt=$(($cnt + 1))
#     echo -n "."
# done

# sleep 5

runclients() {
    echo "Starting clients..."

    # Now send messages to each other
    CTR=0
    for cid in $(seq 4 7)
    do
        # TODO: Change the recipients to send multiple messages. We can't
        #       run multiple clients with the same user id so we need
        #       updates to make that work.
        #     for nid in 1 2 3 4; do
        for nid in 1
        do
            nid=$(((($cid + 1) % 4) + 4))
            eval NICK=\${NICK${cid}}
            # Send a regular message
            mkdir -p blob$cid
            CLIENTCMD="timeout 120s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client$cid$nid.log -s blob$cid/blob$cid --unsafe --sendid $cid --destid $nid --waitTimeout 70 --sendCount 20 --receiveCount 20 -m \"Hello, $nid\""
            eval $CLIENTCMD >> $CLIENTOUT/client$cid$nid.txt 2>&1 &
            PIDVAL=$!
            eval CLIENTS${CTR}=$PIDVAL
            echo "$CLIENTCMD -- $PIDVAL"
            CTR=$(($CTR + 1))
        done
    done

    echo "WAITING FOR $CTR CLIENTS TO EXIT..."
    for i in $(seq 0 $(($CTR - 1)))
    do
        eval echo "Waiting on \${CLIENTS${i}} ..."
        eval wait \${CLIENTS${i}}
    done
}

echo "RUNNING BASIC CLIENTS..."
runclients
echo "RUNNING BASIC CLIENTS (2nd time)..."
runclients


# Send E2E messages between a single user
mkdir -p blob9
mkdir -p blob18
echo "TEST E2E WITH PRECANNED USERS..."
CLIENTCMD="timeout 90s ../bin/client  $CLIENTOPTS -l $CLIENTOUT/client9.log --sendDelay 1000 --sendCount 2 --receiveCount 2 -s blob9/blob9 --sendid 9 --destid 9 -m \"Hi 9->9, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client9.txt 2>&1 &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
CLIENTCMD="timeout 90s ../bin/client  $CLIENTOPTS -l $CLIENTOUT/client9.log --sendDelay 1000 --sendCount 2 --receiveCount 2 -s blob9/blob9 --sendid 9 --destid 9 -m \"Hi 9->9, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client9.txt 2>&1 &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL

# Send E2E messages between two users
CLIENTCMD="timeout 90s ../bin/client  $CLIENTOPTS -l $CLIENTOUT/client9.log --sendDelay 1000 --sendCount 3 --receiveCount 3 -s blob9/blob9 --sendid 9 --destid 18 -m \"Hi 9->18, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client9.txt 2>&1 &
PIDVAL1=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 90s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client18.log --sendDelay 1000  --sendCount 3 --receiveCount 3 -s blob18/blob18 --sendid 18 --destid 9 -m \"Hi 18->9, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client18.txt 2>&1 &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL1
wait $PIDVAL2


# Send multiple E2E encrypted messages between users that discovered each other
echo "SENDING MESSAGES TO PRECANNED USERS AND FORCING A REKEY..."
CLIENTCMD="timeout 180s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client18_rekey.log --sendCount 20 --receiveCount 20 --destid 9 -s blob18/blob18 -m \"Hello, 9, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client18_rekey.txt 2>&1 || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 180s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client9_rekey.log --sendCount 20 --receiveCount 20 --destid 18 -s blob9/blob9 -m \"Hello, 18, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client9_rekey.txt 2>&1 || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL || true


# Non-precanned E2E user messaging
echo "SENDING E2E MESSAGES TO NEW USERS..."
CLIENTCMD="timeout 210s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blob42 --writeContact rick42-contact.json --unsafe -m \"Hello from Rick42 to myself, without E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client42.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
CLIENTCMD="timeout 210s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client43.log -s blob43 --writeContact ben43-contact.json --destfile rick42-contact.json --waitTimeout 30 --sendCount 0 --receiveCount 0 -m \"Hello from Ben43, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client43.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL2
TMPID=$(cat $CLIENTOUT/client42.log | grep "User\:" | awk -F' ' '{print $5}')
RICKID=${TMPID}
echo "RICK ID: $RICKID"
TMPID=$(cat $CLIENTOUT/client43.log | grep "User\:" | awk -F' ' '{print $5}')
BENID=${TMPID}
echo "BEN ID: $BENID"

# Test destid syntax too, note wait for 11 messages to catch the message from above ^^^
CLIENTCMD="timeout 210s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blob42 --destid b64:$BENID --sendCount 5 --receiveCount 5 -m \"Hello from Rick42, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client42.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 210s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client43.log -s blob43 --destid b64:$RICKID --sendCount 5 --receiveCount 5 -m \"Hello from Ben43, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client43.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2
CLIENTCMD="timeout 210s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client42.log -s blob42 --destid b64:$BENID --sendCount 5 --receiveCount 5 -m \"Hello from Rick42, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client42.txt || true &
PIDVAL=$!
echo "$CLIENTCMD -- $PIDVAL"
CLIENTCMD="timeout 210s ../bin/client $CLIENTOPTS -l $CLIENTOUT/client43.log -s blob43 --destid b64:$RICKID --sendCount 5 --receiveCount 5 -m \"Hello from Ben43, with E2E Encryption\""
eval $CLIENTCMD >> $CLIENTOUT/client43.txt || true &
PIDVAL2=$!
echo "$CLIENTCMD -- $PIDVAL"
wait $PIDVAL
wait $PIDVAL2

cp $CLIENTOUT/*.txt $CLIENTCLEAN/

sed -i 's/Sending\ to\ .*\:/Sent:/g' $CLIENTCLEAN/client4[23].txt
sed -i 's/Message\ from\ .*, .* Received:/Received:/g' $CLIENTCLEAN/client4[23].txt
sed -i 's/ERROR.*Signature/Signature/g' $CLIENTCLEAN/client*.txt
sed -i 's/uthenticat.*$//g' $CLIENTCLEAN/client*.txt

# for C in $(ls -1 $CLIENTCLEAN); do
#     sort -o tmp $CLIENTCLEAN/$C  || true
#     uniq tmp $CLIENTCLEAN/$C || true
# done

set -e


echo "TESTS EXITED SUCCESSFULLY, CHECKING OUTPUT..."
set +x
diff -ruN clients.goldoutput $CLIENTCLEAN

#cat $CLIENTOUT/* | strings | grep -e "ERROR" -e "FATAL" > results/client-errors || true
#diff -ruN results/client-errors.txt noerrors.txt
cat $SERVERLOGS/server-*.log | grep "ERROR" | grep -v "context" | grep -v "metrics" | grep -v "database" > results/server-errors.txt || true
cat $SERVERLOGS/server-*.log | grep "FATAL" | grep -v "context" | grep -v "transport is closing" | grep -v "database" >> results/server-errors.txt || true
diff -ruN results/server-errors.txt noerrors.txt
cat $DUMMYOUT | grep "ERROR" | grep -v "context" | grep -v "failed\ to\ read\ certificate" > results/dummy-errors.txt || true
cat $DUMMYOUT | grep "FATAL" | grep -v "context" >> results/dummy-errors.txt || true
diff -ruN results/dummy-errors.txt noerrors.txt
IGNOREMSG="GetRoundBufferInfo: Error received: rpc error: code = Unknown desc = round buffer is empty"
cat $GATEWAYLOGS/*.log | grep "ERROR" | grep -v "context" | grep -v "certificate" | grep -v "Failed to read key" | grep -v "$IGNOREMSG" > results/gateway-errors.txt || true
cat $GATEWAYLOGS/*.log | grep "FATAL" | grep -v "context" | grep -v "transport is closing" >> results/gateway-errors.txt || true
diff -ruN results/gateway-errors.txt noerrors.txt

echo "NO OUTPUT ERRORS, SUCCESS!"
