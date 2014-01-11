#!/usr/bin/ruby
# -*- coding: utf-8 -*-
# Example 3 : gdb を使用したちょっと凝った例
#             'enq: XX - XXXXXXX' 待機状態となったときに止める
# 実行方法 : ruby ex3_gdb_complex.rb

require '../repro'

ss = Repro::ScreenSession.new

ses1 = Repro::SQLPlus.new(ss.new_window)
ses1.title("waiter")
ses2 = Repro::SQLPlus.new(ss.new_window)
ses2.title("holder")
gdb = Repro::GDB.new(ss.new_window)
gdb.title("gdb")

ses1.cmd("connect scott/tiger")
ses2.cmd("connect scott/tiger")

# oracle の path を取得
sh = Repro::Shell.new(ss.new_window)
oracle_path = sh.cmd("which oracle")
sh.close

# ses1 の oracle プロセスの OS pid, ORACLE SESSION ID を取得
sys = Repro::SQLPlus.new(ss.new_window)
sys.title("sys")
sys.cmd("connect /as sysdba")
spid1 = sys.cmd("select p.spid from v$session s, v$process p where s.process = #{ses1.pid} and s.paddr = p.addr;").slice(/^\s*[0-9]+\s*$/).strip
sid1 = sys.cmd("select sid from v$session where process = #{ses1.pid};").slice(/^\s*[0-9]+/).strip

gdb.cmd("file #{oracle_path}")
gdb.cmd("attach #{spid1}")

ses2.cmd("update emp set sal = sal where empno = 7369;")
ses1.cmd_no_wait("update emp set sal = sal where empno = 7369;")

gdb.cmd("b updexe")
gdb.cmd("c")
last_func = "updexe ()"
gdb.cmd("b ksqcmi")
gdb.cmd("c")
last_func = "ksqcmi ()"

event = String.new
timeout_last_time = false
# v$session_wait.event 列が /enq/ にマッチしたときにループを抜ける
until event =~ /enq/
  # 次の関数に辿り着くまで stepi 実行
  func = gdb.cmd("si").slice(/\w+ \(\)/) while func == last_func

  # /lib64 配下の関数はスキップする
  if gdb.cmd("si") =~ /from \/lib64/
    gdb.cmd("finish")
    next
  end

  last_func = func
  
  if timeout_last_time == false
    event = sys.cmd("select event from v$session_wait where sid = #{sid1};", 1)
  else
    event = sys.wait_prompt(1)
  end

  if event.nil?
    timeout_last_time = true
  else
    timeout_last_time = false
  end
end

gdb.cmd("bt")

ss.detach
