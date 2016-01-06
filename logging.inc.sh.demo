#!/bin/bash

logs_dir="$HOME/backup_logs"
mkdir -p "$logs_dir"

function log_success () { echo "$@" | tee "$logs_dir/info.log"; }
function log_info ()    { echo "$@" | tee "$logs_dir/info.log"; }
function log_warning () { echo "$@" | tee "$logs_dir/problems.log"; }
function log_failure () { echo "$@" | tee "$logs_dir/problems.log"; }


