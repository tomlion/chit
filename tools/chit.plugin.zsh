_chit_cache_task_list=1

# Cache filename
_chit_task_cache_file='.chits_cache'

_chit_get_target_list () {
  chit all
}

_chit_does_target_list_need_generating () {

	if [ ${_chit_cache_task_list} -eq 0 ]; then
		return 1;
	fi

	if [ ! -f ${_chit_task_cache_file} ]; then return 0;
	else
		#accurate=$(stat -f%m $_chit_task_cache_file)
		#changed=$(stat -f%m chitfile)
		#return $(expr $accurate '>=' $changed)
    return 0;
	fi
}

_chit () {
  if _chit_does_target_list_need_generating; then
    _chit_get_target_list > ${_chit_task_cache_file}
    compadd `cat ${_chit_task_cache_file}`
  else
    compadd `_chit_get_target_list`
  fi
}

compdef _chit chit

alias chits='chit all'
