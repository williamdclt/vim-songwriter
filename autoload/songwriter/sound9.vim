vim9script
# autoload/songwriter/sound9.vim - songwriter#sound#Pluck in compiled Vim9
# script, for Vim 9 (see sound.vim). The two must give the same bytes
# (test/songwriter_sound.vader).

export def Pluck(ks: dict<any>): blob
  var buf: list<float> = ks.buf
  var a: float = ks.a
  var b: float = ks.b
  var c: float = ks.c
  var n: number = ks.n
  var fade: number = ks.fade
  var level: float = ks.level
  var p = len(buf)
  var data: list<number> = []
  var j = 0
  var x1 = 0.0
  var y1 = 0.0
  for i in range(n)
    var s = buf[j]
    var next = j + 1 < p ? j + 1 : 0
    var x = a * s + b * buf[next]
    var y = c * x + x1 - c * y1
    x1 = x
    y1 = y
    buf[j] = y
    j = next
    var gain = i < n - fade ? level : level * (n - i) / fade
    var v = float2nr(s * gain)
    v = v < 0 ? v + 65536 : v
    data->add(and(v, 255))
    data->add(v / 256)
  endfor
  return list2blob(data)
enddef
