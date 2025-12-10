rm mur.o
as mur.asm -n -g -O0 --64 -am -amhls=mur.lst -o mur.o
ld mur.o -N -o mur
mv mur moor
