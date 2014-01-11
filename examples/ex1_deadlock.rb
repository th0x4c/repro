#!/usr/bin/ruby
# -*- coding: utf-8 -*-
# Example 1 : デッドロック
# 実行方法 : ruby ex1_deadlock.rb

require '../repro'

ss = Repro::ScreenSession.new

ses1 = Repro::SQLPlus.new(ss.new_window)
ses2 = Repro::SQLPlus.new(ss.new_window)

ses1.title("Ses1")
ses2.title("Ses2")

ses1.cmd("connect scott/tiger")
ses2.cmd("connect scott/tiger")
ses1.cmd("-- #{Time.now}")
ses1.cmd("update emp set sal = sal where empno = 7369;")
ses2.cmd("-- #{Time.now}")
ses2.cmd("update emp set sal = sal where empno = 7788;")
ses1.cmd("-- #{Time.now}")
ses1.cmd_no_wait("update emp set sal = sal where empno = 7788;")
ses2.cmd("-- #{Time.now}")
ses2.cmd_no_wait("update emp set sal = sal where empno = 7369;")

ses1.wait_prompt

ss.detach
