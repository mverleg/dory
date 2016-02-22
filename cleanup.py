
from argparse import ArgumentParser
from datetime import datetime, timedelta
from os import listdir
from os.path import join
from random import randint
from re import findall
from shutil import rmtree


def find_backups(dir, dry=True):
	for name in listdir(dir):
		match = findall(r'backup_(\d+)-(\d+)-(\d+)-(\d+)-(\d+)-(\d+)', name)
		if match:
			dt = datetime(2000+int(match[0][0]), *tuple(int(v) for v in match[0][1:]))
			if dry:
				yield None, dt
			else:
				yield name, dt


def remove(days, which, dir):
	print('remove {0:}'.format(days[which][0] or days[which][1]))
	if days[which][0]:
		budir = join(dir, days[which][0])
		rmtree(budir)
	days.pop(which)


def get_scores(days, now):
	diffs = [0] * len(days)
	ago = [0] * len(days)
	for k, day1 in enumerate(days):
		age = abs((now - day1[1]).total_seconds()) / 86400
		ago[k] = age
		for day2 in days:
			diff = abs(int((day1[1] - day2[1]).total_seconds()))
			if diff > 0:
				score = 1.e6 / diff
				diffs[k] += score
		diffs[k] = (diffs[k] * age**0.5)
	return ago, diffs


def get_top(collection):
	topk, topval = None, -float('inf')
	for k, val in enumerate(collection):
		if val > topval:
			topk, topval = k, val
	if topk is None:
		raise AssertionError('didn\'t find a maximum in {0:}'.format(collection))
	return topk, topval


def get_args():
	parser = ArgumentParser(description='Remove old backup files.')
	parser.add_argument('directory', type=str, help='Directory where backups are stored (should be named e.g. backup_16-01-09-20-31-24)')
	parser.add_argument('--maxage', type=int, default=90, help='Maximum age in days (older backups are always removed).')
	parser.add_argument('--keep', type=int, default=10, help='How many backups to keep (any excess ones are removed).')
	parser.add_argument('--plot', action='store_true', help='Show a plot of backups and scores.')
	parser.add_argument('--demo', type=int, default=None, help='Use X demo data points instead (also implies --dry).')
	parser.add_argument('--dry', action='store_true', help='Just show what to remove but don\'t actually do it.')
	args = parser.parse_args()
	assert args.keep >= 1
	return args


def prune(args):
	now = datetime.now()

	if args.demo is not None:
		days = [(None, now - timedelta(days=int((0.03 * randint(0, int(100)))**4), seconds=randint(0, 86400))) for k in range(args.demo)]
	else:
		days = list(find_backups(args.directory, args.dry))

	fig = ax = mp = None
	if args.plot:
		from matplotlib.pyplot import subplots
		fig, ax = subplots(figsize=(8, 4))
		ax.set_xlabel('Days ago')
		ax.set_ylabel('Redundancy score')
		ax.set_yscale('log')
		original_ago, original_scores = get_scores(days, now)
		ax.scatter(original_ago, original_scores, color='red')
		mp = {ago: score for ago, score in zip(original_ago, original_scores)}

	for k in reversed(range(len(days))):
		if (now - days[k][1]).total_seconds() > 24 * 60 * 60 * (args.maxage + 0.5):
			remove(days, k, args.directory)

	while len(days) > args.keep:
		ago, scores = get_scores(days, now)
		topk, topscore = get_top(scores)
		remove(days, topk, args.directory)

	if fig and ax and mp:
		from matplotlib.pyplot import show
		ago = get_scores(days, now)[0]
		ax.scatter(ago, tuple(mp[a] for a in ago), color='blue')
		ax.set_ylim([min(mp.values()), max(mp.values())])
		show()


if __name__ == '__main__':
	prune(get_args())


