rm mur.o
as mur.asm --defsym ORG=0 -n -g -O0 --64 -am -amhls=mur.lst -o mur.o
ld mur.o -N -o mur
mv mur moor

rm mur.o
as mur.asm --defsym ORG=0 --defsym DEBUG=1 -n -g -O0 --64 -am -amhls=mur.lst -o mur.o
ld mur.o -N -o mur
mv mur moord

rm mur.o
as mur.asm --defsym ORG=0 --defsym DEBUG=1 --defsym TRACE=1 -n -g -O0 --64 -am -amhls=mur.lst -o mur.o
ld mur.o -N -o mur
mv mur moordt

