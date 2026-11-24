#!/bin/bash
# Corre os testes e grava frame.png. Usar no WSL (Ubuntu-22.04, com o oss-cad-suite).
set -e
cd "$(dirname "$0")"
OSS=~/oss-cad-suite/bin
$OSS/iverilog -g2012 -Wall -Wno-timescale -o tb.vvp tb.v ../src/*.v
$OSS/vvp -n tb.vvp
python3 -I ppm2png.py frame.ppm frame.png
echo "imagem: sim/frame.png"
