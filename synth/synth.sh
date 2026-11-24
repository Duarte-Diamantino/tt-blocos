#!/bin/bash
# Síntese com o Yosys contra a biblioteca sky130_fd_sc_hd e área face a um tile 1x1.
# Usar no WSL (Ubuntu-22.04, com o oss-cad-suite e ~/pdk).
# Nota: é só síntese; o place & route (GitHub Action do Tiny Tapeout) acrescenta área.
cd "$(dirname "$0")"
LIB=~/pdk/sky130_fd_sc_hd__tt_025C_1v80.lib
YOSYS=~/oss-cad-suite/bin/yosys
TILE=17955   # tile 1x1 SKY130: 161.00 x 111.52 um
TOP=tt_um_duarte_diamantino_blocos
SRC="../src/pieces.v ../src/vga_sync.v ../src/game.v ../src/$TOP.v"
OUT=results
mkdir -p $OUT

# por módulo (para ver onde vai a área)
$YOSYS -q -l $OUT/hier.log -p "
  read_verilog $SRC
  synth -top $TOP
  dfflibmap -liberty $LIB
  abc -liberty $LIB
  opt_clean
  tee -q -o $OUT/hier.stat stat -liberty $LIB
" > /dev/null

# desenho completo achatado (número final)
$YOSYS -q -l $OUT/flat.log -p "
  read_verilog $SRC
  synth -top $TOP -flatten
  check
  dfflibmap -liberty $LIB
  abc -liberty $LIB
  opt_clean
  tee -q -o $OUT/flat.stat stat -liberty $LIB
" > /dev/null

AREA=$(grep "Chip area" $OUT/flat.stat | awk '{print $NF}')
FFS=$(grep -E "sky130_fd_sc_hd__(e?df|dl)" $OUT/flat.stat | awk '{s+=$1} END{print s+0}')
echo "AREA: $AREA um2 = $(awk -v a="$AREA" -v t=$TILE 'BEGIN{printf "%.1f", 100*a/t}')% de um tile 1x1, $FFS flip-flops"
echo
echo "=== por modulo ==="
grep -E "^=== |Chip area" $OUT/hier.stat
echo
echo "=== avisos ==="
grep -i "warning" $OUT/flat.log | grep -v "ABC: Warning" | sort | uniq -c | head -20
