default:
	@just --list

alias c := commit
commit msg:
	git add . && git commit -m "{{msg}}" && git push
