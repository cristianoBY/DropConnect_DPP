vars='79 157 236 314 392 471 549 628 706'
rounds='1 2 3 4 5 6 7 8 9 10'
for round in $rounds
do
	filename="rand_edge_MNIST_0.0_batch1000_output_round${round}.txt"
	for var in $vars
	do
		echo '============================================================' 2>> $filename
		python3 MNIST.py --pruning_choice random_edge --k $var --procedure pruning >> $filename
	done
done