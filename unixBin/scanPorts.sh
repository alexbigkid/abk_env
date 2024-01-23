#! /bin/bash
echo "Starting IP: "
read IP1
resultFile="ScanResult${IP1}"

# echo "Last octet of the last IP address: "
# read LastOctet

echo "Port number: "
read Port

# nmap -sT $IP1-$LastOctet  -p $Port >/dev/null -oG Scan
nmap -sT $IP1-255  -p $Port >/dev/null -oG Scan
cat Scan | grep open > resultFile
cat resultFile

