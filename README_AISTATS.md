
# Requirements
```
torch==1.3.1
torchvision==0.4.2
dppy==0.2.0
numpy==1.17.2
jupyter==1.0.0
scikit-learn==0.20.2
```
It is suggested to create a python virtual env with the above dependencies. 


## Possible Env. Error
For MNIST, please make sure you use the data from http://yann.lecun.com/exdb/mnist/train-images-idx3-ubyte.gz. It should be automatically downloaded by our MNIST code via torchvision.

We have observed issues in https://github.com/pytorch/vision/issues/1712, where the new Pillow (7.0.0) package having a conflict with torchvision.

In this case, do `pip install pillow==6.1` will solve it, as proposed online.


## To perform DPP purning and simulations in the teacher-student setup

Generating dataset and the teacher network:
>python3 teacher_dataset.py --input_dim 500 --teacher_h_size 2 --teacher_path teacher.pkl --num_data 800000 --mode normal --sig_w 0 --v_star 4

with the following arguments:
```
	# network parameter
	parser.add_argument('--input_dim', type = int, help='The input dimension for each data point.')
	parser.add_argument('--teacher_h_size', type = int, help='hidden layer size of the student MLP')
	parser.add_argument('--num_data', type = int, help='Number of data points to be genrated.')
	parser.add_argument('--mode', type = str, help='soft_committee or normal')
	parser.add_argument('--sig_w', type = float, help='scaling variable for the output noise.')
	parser.add_argument('--v_star', type = int, help='ground truth second layer weight')

	# data storage
	parser.add_argument('--teacher_path', type = str, help='Path to store the teacher network and dataset.')
```

Training the student network:
>python3 teacher_student.py --input_dim 500 --student_h_size 6 --teacher_path teacher.pkl  --nonlinearity sigmoid  --mode normal  --epoch 1 --lr 0.5

Pruning the student network:
>python3 teacher_student.py --input_dim 500 --student_h_size 6 --teacher_path teacher.pkl  --nonlinearity sigmoid --pruning_choice dpp_node  --mode normal  --trained_weights student_6.pth --procedure pruning --num_masks 100 --k 3


with the following arguments:
```
	# network parameter
	parser.add_argument('--input_dim', type = int, help='The input dimension for each data point.')
	parser.add_argument('--student_h_size', type = int, help='hidden layer size of the student MLP')
	parser.add_argument('--nonlinearity', type = str, help='choice of the activation function')
	parser.add_argument('--mode', type = str, help='soft_committee or normal')

	# optimization setup
	parser.add_argument('--lr', type=float, default=0.5, metavar='LR',
						help='learning rate (default: 0.5) that will be scaled for each layer accordingly')
	parser.add_argument('--momentum', type=float, default = 0, metavar='M',
						help='SGD momentum (default: 0)')
	parser.add_argument('--epoch', type = int, default = 1, help='number of epochs (online learning so 1)')
	parser.add_argument('--seed', type=int, default=1, metavar='S',
						help='random seed (default: 1)')

	# pruning parameters
	parser.add_argument('--pruning_choice', type = str, default = 'dpp_node',
						help='pruning options.')
	parser.add_argument('--beta', type = float, default = 0.3,
						help='beta for dpp')
	parser.add_argument('--k', type = int, default = 2,
						help='number of parameters to preserve (for node pruning: # of nodes; for edge pruning: # of weights per node)')
	parser.add_argument('--procedure', type = str, default = 'training',
						help='training, pruning, or testing')
	parser.add_argument('--num_masks', type = int, default = 1,
						help='Number of masks to be sampled by DPP.')
	# data storage
	parser.add_argument('--trained_weights', type = str, default = 'place_holder', help='path to the trained weights for loading')
	parser.add_argument('--teacher_path', type = str, help='Path to the teacher network and dataset.')
```

The above process produces a output pickle named as `'student_masks_' + args.pruning_choice + '_' + str(args.student_h_size) + "_" + str(args.k) + '.pkl'`. It contains the unpruned student network and the masks sampled by DPP in a list.


To get the order parameters (Q, T, R) of the networks:
>python3 evaluate.py --path_to_student_mask student_masks_dpp_node_6_3.pkl --path_to_teacher teacher.pkl --input_dim 500

Make sure the arguments passed in are correct since it will loads the pickle file `'student_masks_' + args.pruning_choice + '_' + str(args.student_h_size) + "_" + str(args.k) + '.pkl'` from the previous pruning step.

If the `evaluate.py` throws an index-out-of-bound error, it indicates that the training did not converge so that the code for aligning block diagonal matrix cannot be executed. Please refer to the appendix and simulation section on what hyperparameters we used. 


## Fixing the finite DPP sampling of the Dppy package

Specifically, the problems affects the K-DPP samping method, `DPP.sample_exact_k_dpp(size = k)`, of the Dppy package. The error looks like below:
```
  File "/dpp_sample_ts.py", line 22, in sample_dpp_multiple_ts
    DPP.sample_exact_k_dpp(size = k)
  File "/dpp_test/lib/python3.7/site-packages/dppy/finite_dpps.py", line 478, in sample_exact_k_dpp
    random_state=rng)
  File "/dpp_test/lib/python3.7/site-packages/dppy/exact_sampling.py", line 461, in proj_dpp_sampler_eig
    sampl = proj_dpp_sampler_eig_GS(eig_vecs, size, rng)
  File "/dpp_test/lib/python3.7/site-packages/dppy/exact_sampling.py", line 531, in proj_dpp_sampler_eig_GS
    p=np.abs(norms_2[avail]) / (rank - it))
  File "mtrand.pyx", line 926, in numpy.random.mtrand.RandomState.choice
ValueError: probabilities do not sum to 1
```

After contacting the author, we learned that this is caused the floating point rounding error.  Fortunately, there is a simple fix in our case. In `site-packages/dppy/exact_sampling.py`, line 531, in the `proj_dpp_sampler_eig_GS` method, modify the original code:
```
    for it in range(size):
        # Pick an item \propto this squred distance
        j = rng.choice(ground_set[avail],
                             p=np.abs(norms_2[avail]) / (rank - it))
```
to
```
    for it in range(size):
        # Pick an item \propto this squred distance
        arr = np.abs(norms_2[avail]) / (rank - it)
        arr = arr / np.sum(arr)
        j = rng.choice(ground_set[avail], p=arr)
```

This is simply a re-normalization of the probability, and it does not affect our experimental results. All of our experimental results complies with our theoratical justifications. This is purely a floating point rounding bug.


## To compare different pruning methods on the test dataset

>python3 teacher_student.py --input_dim 500 --student_h_size 6 --teacher_path teacher.pkl  --nonlinearity sigmoid --pruning_choice imp_edge  --mode normal  --trained_weights student_6.pth --procedure pruning --num_masks 100 --k 50

stricly followed by

>python3 teacher_student.py --input_dim 500 --student_h_size 6 --teacher_path teacher.pkl  --nonlinearity sigmoid  --mode normal  --trained_weights student_6.pth --procedure testing --pruning_choice imp_edge --k 50


Change the argument `--pruning_choice` to compare between methods such as `dpp_node` and `imp_edge`. NOTICE: Run the above command consecutively; keep the `--student_h_size`, `--k`, and `--pruning_choice` consistent and correct; be CAREFUL with `--procedure` and the `--input_dim` when calculating the number of parameters.

Node-Edge correspondence (`--k`):

Given 6 student nodes and the input dimension, the number of remaining weghts are

|Node   |Edge (inp_dim = 100)  	|Edge (inp_dim = 500)  	|
|---	|---	|---
|1   	|16   	|83   	|
|2  	|33 	|166   	|
|3  	|50  	|250   	|
|4  	|66   	|333   	|
|5  	|83   	|417   	|

