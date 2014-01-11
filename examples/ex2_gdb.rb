#!/usr/bin/ruby
# -*- coding: utf-8 -*-
# Example 2 : gdb を使用した例
# 実行方法 : ruby ex2_gdb.rb

require '../repro'

ss = Repro::ScreenSession.new

# oracle バイナリのパスを取得
sh = Repro::Shell.new(ss.new_window)
oracle_path = sh.cmd("which oracle")
sh.close

ses = Repro::SQLPlus.new(ss.new_window)
ses.cmd("connect scott/tiger")
ses.title("sqlplus")

gdb = Repro::GDB.new(ss.new_window)
gdb.title("gdb")

# oracle プロセスの OS pid を取得
sys = Repro::SQLPlus.new(ss.new_window)
sys.cmd("connect /as sysdba")
spid = sys.cmd("select p.spid from v$session s, v$process p where s.process = #{ses.pid} and s.paddr = p.addr;").slice(/^[0-9]+$/)
sys.close

# oracle プロセスへのアタッチ
gdb.cmd("file #{oracle_path}")
gdb.cmd("exec-file #{oracle_path}")
gdb.cmd("attach #{spid}")

gdb.cmd("bt")
gdb.cmd("b ksqcmi")
gdb.cmd_no_wait("c")

ses.cmd("update emp set sal = sal where empno = 7369;")
ses.cmd_no_wait("rollback;")

gdb.wait_prompt
output = gdb.cmd("bt")

ss.detach

File.open("output.txt", "w") do |f|
  f.puts "================== Back Trace =================="
  f.puts output
end
