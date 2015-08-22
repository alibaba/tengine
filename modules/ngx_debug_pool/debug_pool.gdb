# compile nginx/tengine with mod_debug_pool module
define debug_pool
  set $_i = 0
  set $_ss = 0
  set $_ns = 0
  set $_cs = 0
  set $_ls = 0
  while $_i < 997
    set $_ps = ngx_pool_stats[$_i]
    while $_ps != 0x0
      printf "size:%12u num:%12u cnum:%12u lnum:%12u %s:%d\n", \
        $_ps->size, $_ps->num, $_ps->cnum, $_ps->lnum, $_ps->func, $_i
      set $_ss = $_ss + $_ps->size
      set $_ns = $_ns + $_ps->num
      set $_cs = $_cs + $_ps->cnum
      set $_ls = $_ls + $_ps->lnum
      set $_ps = $_ps->next
    end
    set $_i = $_i + 1
  end
  printf "size:%12u num:%12u cnum:%12u lnum:%12u [SUMMARY]\n", $_ss, $_ns, $_cs, $_ls
end
