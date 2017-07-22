#include <cuda_device_runtime_api.h>
#include <cuda_runtime_api.h>
#include <device_launch_parameters.h>
#include <driver_types.h>
#include <errno.h>
#include <host_defines.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <time.h>
#include <vector_types.h>

// CUDA device Max Thread Blocks
int THREADS_PER_BLOCK = 32;

clock_t start, end;
extern int errno; // globally holds the error no
int data_size; // holds the data set size read from .cxt file
int attribute_size; // holds the attribute size read from .cxt file
int *cross_table; // holds data set matrix cross table from .cxt file
int concept_count = 0; // holds generated concept count

// define concept_t for hold each concept objects and attribute sets
typedef struct {
	int *objects;
	int *attributes;
} concept_t;

concept_t *concept_latice; // holds main concept latice, generated output

// local functions
void loadData(char *file_path);
void buildInitialConcept(int obj[], int attr[]);
void computeConceptFrom(int *obj, int *attr, int attr_index);
void processConcept(int *obj, int *attr);
bool checkAttribute(int j, int *attr);
void makeExtent(int *extent, int *obj, int attr_index);
void makeIntent(int *intent, int *extent, int attr_index);
bool canonicity(int *attr, int *intent, int attr_index);
int getBlocksPerGrid(int size);

// CUDA Device variables
size_t pitch;
int *d_cross_table; // holds device cross table

// CUDA Kernels
__global__ void processConceptKernel(int *set_1, int *set_2, int size);
__global__ void makeExtentKernel(int *extent, int *obj, int *cross_objects,
		int attr_index, int rows, int cols);
__global__ void makeIntentKernelOnExtentEmpty(int *extent, int *empty_count,
		int size);
__global__ void makeIntentKernel(int *intent, int *extent, int *cross_objects,
		int empty_count, int rows, int cols);
__global__ void canonicityKernel(int *set_1, int *set_1_c, int *set_2,
		int *set_2_c, int *attr, int *intent, int cols);
__global__ void canonicityKernelSetCheck(int *set_1, int *set_2, bool *status,
		int cols);

int main(int argc, char *argv[]) {
	loadData(argv[1]); // read data from file path

	// --------------------------------------------------------------------------------------------------------------
	// allocate device cross table
	cudaError_t cudaStatus;
	cudaStatus = cudaMallocPitch(&d_cross_table, &pitch,
			sizeof(int) * attribute_size, data_size);
	if (cudaStatus != cudaSuccess) {
		printf("cudaMalloc failed");
	}
	// copy data to device - cross_table
	cudaStatus = cudaMemcpy(d_cross_table, cross_table,
			attribute_size * sizeof(int) * data_size, cudaMemcpyHostToDevice);
	cudaDeviceSynchronize(); // force host tp pause until the copying is done
	if (cudaStatus != cudaSuccess) {
		printf("cudaMemcpy2D failed");
	}
	// --------------------------------------------------------------------------------------------------------------

	int ini_obj[data_size]; // initial concept object list
	int ini_attr[attribute_size]; // initial concept attribute list
	buildInitialConcept(ini_obj, ini_attr); // make object and attribute list

	concept_latice = (concept_t *) malloc(
			data_size * attribute_size * sizeof(concept_t *)); // allocate memory on concept latice

	start = clock(); // start timing
	computeConceptFrom(ini_obj, ini_attr, 0); // invoke Close-by-One
	end = clock(); // stop timing

	printf("\nTotal Concepts : %d\n\n", concept_count);
	printf("execution time : %f seconds\n\n",
			((double) (end - start) / CLOCKS_PER_SEC));

	// --------------------------------------------------------------------------------------------------------------
	cudaFree(d_cross_table);
	// --------------------------------------------------------------------------------------------------------------

	free(cross_table);
	free(concept_latice);

	return 0;
}

// load data set file from given location
void loadData(char *file_path) {
	int errnum;
	FILE *file;
	if ((file = fopen(file_path, "rt")) == NULL) {
		errnum = errno;
		fprintf(stderr, "Value of errno: %d\n", errno);
		perror("Error printed by perror");
		fprintf(stderr, "Error opening file: %s\n", strerror(errnum));
	} else {
		printf("\n~~~ Dataset Cross Table ~~~\n\n");

		char buffer[256];
		int line_count = 0;
		int obj_count = 0;
		int atr_count = 0;
		while (fgets(buffer, sizeof(buffer), file)) {
			// process lines
			if (buffer[0] == '\n') {
				// new line found
			} else {
				// skip first character on the .cxt file
				if (line_count != 0) {
					if (line_count == 1) {
						// data size found
						data_size = atoi(buffer);
					} else if (line_count == 2) {
						// attribute size found
						attribute_size = atoi(buffer);
						cross_table = (int *) malloc(
								sizeof(int) * attribute_size * data_size); // allocate cross table matrix
					} else if (line_count > (2 + data_size)
							&& line_count <= (2 + data_size + attribute_size)) {
						// read attributes
						atr_count++;
						obj_count = 0; // reset obj count
					} else if (line_count > (2 + data_size + attribute_size)) {
						// read cross table
						int x;
						for (x = 0; x < attribute_size; x++) {
							// check attribute present or not
							if (buffer[x] == 'X') {
								cross_table[obj_count * attribute_size + x] = 1; // assign one when 'X'
							} else {
								cross_table[obj_count * attribute_size + x] = 0; // assign zero when '.'
							}
							printf("%d",
									cross_table[obj_count * data_size + x]);
						}
						printf("\n");
						obj_count++;
					}
				}
				line_count++;
			}
		}
		fclose(file);
		printf("\n");
	}
}

// build up initial concept
// out: objects, attributes
void buildInitialConcept(int obj[], int attr[]) {
	int i;
	int a;
	/**
	 * assign objects
	 * pass all objects into list, according to the theorem, (X)
	 */
	for (i = 0; i < data_size; i++) {
		obj[i] = i;
	}

	/**
	 * assign attributes
	 * set common attribute list for all objects on cross table (X up)
	 */
	// go through attributes
	for (a = 0; a < attribute_size; a++) {
		bool status = true;
		// go through objects
		for (i = 0; i < data_size; i++) {
			if (cross_table[i * attribute_size + a] == 0) {
				status = false;
				break;
			}
		}
		if (status) {
			// attribute available for all objects, assign 1
			attr[a] = 1;
		} else {
			attr[a] = 0;
		}
	}
}

/**
 * Close-by-One Algorithm
 *
 * input :  1. object list
 *          2. attribute list
 *          3. current attribute index
 */
void computeConceptFrom(int *obj, int *attr, int attr_index) {
	// 1. Process Concept
	processConcept(obj, attr);
	// 2. go through attribute list
	int j;
	for (j = attr_index; j < attribute_size; j++) {
		// 3. check current attribute exist or not
		if (!checkAttribute(j, attr)) {
			// 4. make extent
			int extent[data_size];
			makeExtent(extent, obj, j);
			// 5. make intent
			int intent[attribute_size];
			makeIntent(intent, extent, j);
			// 6. do canonicity test
			if (canonicity(attr, intent, j)) {
				// 7. call computeConceptFrom
				computeConceptFrom(extent, intent, (j + 1));
			}
		}
	}
}

// store concept
void processConcept(int *obj, int *attr) {
	// set objects details on concept latice
	concept_latice[concept_count].objects = (int *) malloc(
			sizeof(int) * data_size);

	// --------------------------------------------------------------------------------------------------------------
	// >>> Run CUDA Kernel <<<
	int *d_obj;
	int *d_object;
	cudaMalloc((void**) &d_obj, sizeof(int) * data_size);
	cudaMalloc((void**) &d_object, sizeof(int) * data_size);
	cudaMemcpy(d_obj, obj, sizeof(int) * data_size, cudaMemcpyHostToDevice);
	int blocksPerGrid = getBlocksPerGrid(data_size);
	processConceptKernel<<<blocksPerGrid, THREADS_PER_BLOCK>>>(d_obj, d_object,
			data_size);
	cudaMemcpy(concept_latice[concept_count].objects, d_object,
			sizeof(int) * data_size, cudaMemcpyDeviceToHost);
	cudaDeviceSynchronize(); // force host to pause until the copying is done
	cudaFree(d_obj);
	cudaFree(d_object);
	// --------------------------------------------------------------------------------------------------------------

	// set attribute details on concept latice
	concept_latice[concept_count].attributes = (int *) malloc(
			sizeof(int) * attribute_size);

	// --------------------------------------------------------------------------------------------------------------
	// >>> Run CUDA Kernel <<<
	int *d_attr;
	int *d_attributes;
	cudaMalloc((void**) &d_attr, sizeof(int) * attribute_size);
	cudaMalloc((void**) &d_attributes, sizeof(int) * attribute_size);
	cudaMemcpy(d_attr, attr, sizeof(int) * attribute_size,
			cudaMemcpyHostToDevice);
	blocksPerGrid = getBlocksPerGrid(attribute_size);
	processConceptKernel<<<blocksPerGrid, THREADS_PER_BLOCK>>>(d_attr,
			d_attributes, attribute_size);
	cudaMemcpy(concept_latice[concept_count].attributes, d_attributes,
			sizeof(int) * attribute_size, cudaMemcpyDeviceToHost);
	cudaDeviceSynchronize(); // force host to pause until the copying is done
	cudaFree(d_attr);
	cudaFree(d_attributes);
	// --------------------------------------------------------------------------------------------------------------

	concept_count++;
}

// check attribute contains on attribute list or not
bool checkAttribute(int j, int *attr) {
	bool status = true;
	if (attr[j] == 0) {
		status = false;
	}
	return status;
}

// make extent
void makeExtent(int *extent, int *obj, int attr_index) {
	// >>> Run CUDA Kernel <<<
	int *d_obj;
	int *d_extent;
	cudaMalloc((void**) &d_obj, sizeof(int) * data_size);
	cudaMalloc((void**) &d_extent, sizeof(int) * data_size);
	cudaMemcpy(d_obj, obj, sizeof(int) * data_size, cudaMemcpyHostToDevice);
	int blocksPerGrid = getBlocksPerGrid(data_size);
	makeExtentKernel<<<blocksPerGrid, THREADS_PER_BLOCK>>>(d_extent, d_obj,
			d_cross_table, attr_index, data_size, attribute_size);
	cudaMemcpy(extent, d_extent, sizeof(int) * data_size,
			cudaMemcpyDeviceToHost);
	cudaDeviceSynchronize(); // force host to pause until the copying is done
	cudaFree(d_obj);
	cudaFree(d_extent);
}

// make intent
void makeIntent(int *intent, int *extent, int attr_index) {
	int empty_count = 0;

	// check extent is empty set
	// --------------------------------------------------------------------------------------------------------------
	// >>> Run CUDA Kernel <<<
	int *d_extent;
	int *d_empty_count;
	cudaMalloc((void**) &d_extent, sizeof(int) * data_size);
	cudaMalloc((void**) &d_empty_count, sizeof(int));
	cudaMemcpy(d_extent, extent, sizeof(int) * data_size,
			cudaMemcpyHostToDevice);
	cudaMemcpy(d_empty_count, &empty_count, sizeof(int),
			cudaMemcpyHostToDevice);
	int blocksPerGrid = getBlocksPerGrid(data_size);
	makeIntentKernelOnExtentEmpty<<<blocksPerGrid, THREADS_PER_BLOCK>>>(
			d_extent, d_empty_count, data_size);
	cudaMemcpy(&empty_count, d_empty_count, sizeof(int),
			cudaMemcpyDeviceToHost);
	cudaDeviceSynchronize(); // force host to pause until the copying is done
	cudaFree(d_empty_count);
	// --------------------------------------------------------------------------------------------------------------

	// --------------------------------------------------------------------------------------------------------------
	// >>> Run CUDA Kernel <<<
	int *d_intent;
	cudaMalloc((void**) &d_intent, sizeof(int) * attribute_size);
	blocksPerGrid = getBlocksPerGrid(attribute_size);
	makeIntentKernel<<<blocksPerGrid, THREADS_PER_BLOCK>>>(d_intent, d_extent,
			d_cross_table, empty_count, data_size, attribute_size);
	cudaMemcpy(intent, d_intent, sizeof(int) * attribute_size,
			cudaMemcpyDeviceToHost);
	cudaDeviceSynchronize(); // force host to pause until the copying is done
	cudaFree(d_intent);
	// --------------------------------------------------------------------------------------------------------------
}

// perform canonicity test
bool canonicity(int *attr, int *intent, int attr_index) {
	bool status = true;
	int set_1[attr_index];
	int set_2[attr_index];
	int set_1_c = 0; // holds set 1 found count
	int set_2_c = 0; // holds set 2 found count

	// 1. check on attribute list
	// --------------------------------------------------------------------------------------------------------------
	// >>> Run CUDA Kernel <<<
	int *d_set_1;
	int *d_set_2;
	int *d_set_1_c;
	int *d_set_2_c;
	int *d_attr;
	int *d_intent;
	cudaMalloc((void**) &d_set_1, sizeof(int) * attr_index);
	cudaMalloc((void**) &d_set_2, sizeof(int) * attr_index);
	cudaMalloc((void**) &d_set_1_c, sizeof(int));
	cudaMalloc((void**) &d_set_2_c, sizeof(int));
	cudaMalloc((void**) &d_attr, sizeof(int) * attribute_size);
	cudaMalloc((void**) &d_intent, sizeof(int) * attribute_size);
	cudaMemcpy(d_set_1_c, &set_1_c, sizeof(int), cudaMemcpyHostToDevice);
	cudaMemcpy(d_set_2_c, &set_2_c, sizeof(int), cudaMemcpyHostToDevice);
	cudaMemcpy(d_attr, attr, sizeof(int) * attribute_size,
			cudaMemcpyHostToDevice);
	cudaMemcpy(d_intent, intent, sizeof(int) * attribute_size,
			cudaMemcpyHostToDevice);
	int blocksPerGrid = getBlocksPerGrid(attr_index);
	canonicityKernel<<<blocksPerGrid, THREADS_PER_BLOCK>>>(d_set_1, d_set_1_c,
			d_set_2, d_set_2_c, d_attr, d_intent, attr_index);
	cudaMemcpy(&set_1_c, d_set_1_c, sizeof(int), cudaMemcpyDeviceToHost);
	cudaMemcpy(&set_2_c, d_set_2_c, sizeof(int), cudaMemcpyDeviceToHost);
	cudaMemcpy(set_1, d_set_1, sizeof(int) * attr_index,
			cudaMemcpyDeviceToHost);
	cudaMemcpy(set_2, d_set_2, sizeof(int) * attr_index,
			cudaMemcpyDeviceToHost);
	cudaDeviceSynchronize(); // force host to pause until the copying is done
	cudaFree(d_set_1_c);
	cudaFree(d_set_2_c);
	cudaFree(d_attr);
	cudaFree(d_intent);
	// --------------------------------------------------------------------------------------------------------------

	if (set_1_c == 0 && set_2_c == 0) {
		// both are empty set
		status = true;
	} else if ((set_1_c != 0 && set_2_c == 0)
			|| (set_1_c == 0 && set_2_c != 0)) {
		// found some element(s) on either of set
		status = false;
	} else if (set_1_c == set_2_c) {
		// found element(s) on both sets
		// ----------------------------------------------------------------------------------------------------------
		// >>> Run CUDA Kernel <<<
		bool *d_status;
		cudaMalloc((void**) &d_status, sizeof(bool));
		cudaMemcpy(d_status, &status, sizeof(bool), cudaMemcpyHostToDevice);
		blocksPerGrid = getBlocksPerGrid(attr_index);
		canonicityKernelSetCheck<<<blocksPerGrid, THREADS_PER_BLOCK>>>(d_set_1,
				d_set_2, d_status, attr_index);
		cudaMemcpy(&status, d_status, sizeof(bool), cudaMemcpyDeviceToHost);
		cudaDeviceSynchronize(); // force host to pause until the copying is done
		cudaFree(d_status);
		// ----------------------------------------------------------------------------------------------------------
	} else {
		status = false;
	}

	// --------------------------------------------------------------------------------------------------------------
	// clear up device set_1 and set_2
	cudaFree(d_set_1);
	cudaFree(d_set_2);
	// --------------------------------------------------------------------------------------------------------------

	return status;
}

// Generate Blocks Per Grid for given size
int getBlocksPerGrid(int size) {
	int blocksPerGrid = size / THREADS_PER_BLOCK;
	if ((size % THREADS_PER_BLOCK) != 0) {
		blocksPerGrid++;
	}
	return blocksPerGrid;
}

// ******************************************************************************************************************
// CUDA Kernels
// ******************************************************************************************************************

// CUDA Kernel to process - 1 Loop
__global__ void processConceptKernel(int *set_1, int *set_2, int size) {
	int i = (blockIdx.x * blockDim.x) + threadIdx.x;
	if (i < size)
		set_2[i] = set_1[i];
}

// CUDA Kernel to make Extent
__global__ void makeExtentKernel(int *extent, int *obj, int *cross_objects,
		int attr_index, int rows, int cols) {
	int i = (blockIdx.x * blockDim.x) + threadIdx.x;
	if (i < rows) {
		extent[i] = -1;
		if (cross_objects[i * cols + attr_index] == 1 && obj[i] != -1) {
			extent[i] = i;
		}
	}
}

// CUDA Kernel to make Extent Empty count on Intent making
__global__ void makeIntentKernelOnExtentEmpty(int *extent, int *empty_count,
		int size) {
	int i = (blockIdx.x * blockDim.x) + threadIdx.x;
	if (i < size) {
		if (extent[i] == -1) {
			empty_count++;
		}
	}
}

// CUDA Kernel to make Intent
__global__ void makeIntentKernel(int *intent, int *extent, int *cross_objects,
		int empty_count, int rows, int cols) {
	int index = (blockIdx.x * blockDim.x) + threadIdx.x;
	if (index < cols) {
		if (empty_count != rows) {
			bool status = true;
			int i;
			for (i = 0; i < rows; i++) {
				// check extent available
				if (extent[i] != -1) {
					// check related cross table index of current exten attribute availability
					if (cross_objects[i * cols + index] != 1) {
						status = false;
						break;
					}
				}
			}
			if (status) {
				intent[index] = 1;
			} else {
				intent[index] = 0;
			}
		} else {
			intent[index] = 1;
		}
	}
}

// CUDA Kernel to proccess canonicity test
__global__ void canonicityKernel(int *set_1, int *set_1_c, int *set_2,
		int *set_2_c, int *attr, int *intent, int cols) {
	int i = (blockIdx.x * blockDim.x) + threadIdx.x;
	if (i < cols) {
		// check attr set
		if (attr[i] == 1) {
			*set_1_c = *set_1_c + 1;
			set_1[i] = 1;
		} else {
			set_1[i] = 0;
		}

		// check intent set
		if (intent[i] == 1) {
			*set_2_c = *set_2_c + 1;
			set_2[i] = 1;
		} else {
			set_2[i] = 0;
		}
	}
}

// CUDA Kernel to check canonicity test set_1 and set_2 sets data
__global__ void canonicityKernelSetCheck(int *set_1, int *set_2, bool *status,
		int cols) {
	int i = (blockIdx.x * blockDim.x) + threadIdx.x;
	if (i < cols && *status) {
		if (set_1[i] != set_2[i]) {
			*status = false;
		}
	}
}

// ******************************************************************************************************************
