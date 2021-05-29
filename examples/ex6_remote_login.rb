#!/usr/bin/ruby
# -*- coding: utf-8 -*-
# Example 6 : リモートログインする例
#             対象サーバに ruby や screen がインストールされていない場合に有効
# 実行方法 : ruby ex6_remote_login.rb

require '../repro'

REMOTE_HOSTNAME = "remotehost"
REMOTE_PASSWORD = "welcome1"
REMOTE_USER     = "th0x4c"
REMOTE_PORT     = 2222
SU_USER         = "oracle"
SU_PASSWORD     = "oracle"
ORACLE_PATH = "/u01/app/oracle/product/version/db_1/bin/oracle"

ss = Repro::ScreenSession.new

ses = Repro::SQLPlus.new(ss.new_window.ssh(REMOTE_HOSTNAME, REMOTE_PASSWORD, REMOTE_USER, REMOTE_PORT))
ses.cmd("connect scott/tiger@orcl")
ses.title("sqlplus")

gdb = Repro::GDB.new(ss.new_window.ssh(REMOTE_HOSTNAME, REMOTE_PASSWORD, REMOTE_USER, REMOTE_PORT).su(SU_USER, SU_PASSWORD))
gdb.title("gdb")

# oracle プロセスの OS pid を取得
sys = Repro::SQLPlus.new(ss.new_window.ssh(REMOTE_HOSTNAME, REMOTE_PASSWORD, REMOTE_USER, REMOTE_PORT).su(SU_USER, SU_PASSWORD))
sys.cmd("connect sys/oracle as sysdba")
spid = sys.cmd("select p.spid from v$session s, v$process p where s.process = '#{ses.pid}' and s.paddr = p.addr;").slice(/^[0-9]+$/)
sys.close

# oracle プロセスへのアタッチ
gdb.cmd("file #{ORACLE_PATH}")
gdb.cmd("exec-file #{ORACLE_PATH}")
gdb.cmd("attach #{spid}")

gdb.cmd("bt")

ss.detach
