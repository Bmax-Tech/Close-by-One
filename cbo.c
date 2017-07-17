#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdbool.h>
#include <errno.h>
#include <time.h>

clock_t start, end;
extern int errno; // globally holds the error no
int data_size; // holds the data set size read from .cxt file
int attribute_size; // holds the attribute size read from .cxt file
int **cross_table; // holds data set cross table from .cxt file
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

int main(int argc, char *argv[]) {
    loadData(argv[1]); // read data from file path

    int ini_obj[data_size]; // initial concept object list
    int ini_attr[attribute_size]; // initial concept attribute list
    buildInitialConcept(ini_obj, ini_attr); // make object and attribute list

    concept_latice = malloc(
            data_size * attribute_size * sizeof(concept_t *)); // allocate memory on concept latice

    start = clock(); // start timing
    computeConceptFrom(ini_obj, ini_attr, 0); // invoke Close-by-One
    end = clock(); // stop timing

    printf("\nTotal Concepts : %d\n\n", concept_count);
    printf("execution time : %f seconds\n\n", ((double) (end - start) / CLOCKS_PER_SEC));

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
        int data_read_count = 0;
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
                        // set cross table memory
                        cross_table = (int **) malloc(sizeof(int *) * data_size);
                    } else if (line_count > 2 && line_count <= (data_size + 2)) {
                        // read data set objects
                        obj_count++;
                    } else if (line_count > (2 + data_size) && line_count <= (2 + data_size + attribute_size)) {
                        // read attributes
                        atr_count++;
                        obj_count = 0; // reset obj count
                    } else if (line_count > (2 + data_size + attribute_size)) {
                        // read cross table
                        cross_table[obj_count] = (int *) malloc(
                                sizeof(int) * attribute_size); // allocate cross table row
                        int x;
                        for (x = 0; x < attribute_size; x++) {
                            // check attribute present or not
                            if (buffer[x] == 'X') {
                                cross_table[obj_count][x] = 1; // assign one when 'X' 
                            } else {
                                cross_table[obj_count][x] = 0; // assign zero when '.'
                            }
                            printf("%d", cross_table[obj_count][x]);
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
            if (cross_table[i][a] == 0) {
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
    printf("\n-------------------------------\n");
    printf("Concept - %d\n\n", concept_count);
    int i;
    // set objects details on concept latice
//    concept_latice[concept_count] = (concept_t)malloc(sizeof(concept_t));
    concept_latice[concept_count].objects = (int *) malloc(sizeof(int) * data_size);
    printf("Object Set : ");
    for (i = 0; i < data_size; i++) {
        concept_latice[concept_count].objects[i] = obj[i];
        printf("%d ", concept_latice[concept_count].objects[i]);
    }
    printf("\n");
    // set attribute details on concept latice
    concept_latice[concept_count].attributes = (int *) malloc(sizeof(int) * attribute_size);
    printf("Attribute Set : ");
    for (i = 0; i < attribute_size; i++) {
        concept_latice[concept_count].attributes[i] = attr[i];
        printf("%d ", concept_latice[concept_count].attributes[i]);
    }
    printf("\n-------------------------------\n\n");
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
    int i, z;
    printf("extent (attr : %d): ", attr_index);
    // go through cross table
    for (i = 0; i < data_size; i++) {
        extent[i] = -1; // set default value
        if (cross_table[i][attr_index] == 1 && obj[i] != -1) {
            extent[i] = i; // set object index to extent list
        }
        printf("%d ", extent[i]);
    }
    printf("\n");
}

// make intent
void makeIntent(int *intent, int *extent, int attr_index) {
    int i, a;
    int empty_count = 0;
    printf("intent (attr : %d): ", attr_index);
    // check extent is empty set
    for (i = 0; i < data_size; i++) {
        if (extent[i] == -1) {
            empty_count++;
        }
    }
    for (a = 0; a < attribute_size; a++) {
        // validate on empty extent set
        if (empty_count != data_size) {
            bool status = true;
            for (i = 0; i < data_size; i++) {
                // check extent available
                if (extent[i] != -1) {
                    // check related cross table index of current exten attribute availability
                    if (cross_table[i][a] != 1) {
                        status = false;
                        break;
                    }
                }
            }
            if (status) {
                intent[a] = 1;
            } else {
                intent[a] = 0;
            }
        } else {
            intent[a] = 1;
        }
        printf("%d ", intent[a]);
    }
    printf("\n");
}

// perform canonicity test
bool canonicity(int *attr, int *intent, int attr_index) {
    bool status = false;
    int set_1[attr_index];
    int set_2[attr_index];
    int set_1_c = 0;// holds set 1 found count
    int set_2_c = 0;// holds set 2 found count
    int i;
    // 1. check on atribute list
    for (i = 0; i < attr_index; i++) {
        // check attr set
        if (attr[i] == 1) {
            set_1_c++;
            set_1[i] = 1;
        } else {
            set_1[i] = 0;
        }

        // check intent set
        if (intent[i] == 1) {
            set_2_c++;
            set_2[i] = 1;
        } else {
            set_2[i] = 0;
        }
    }

    if (set_1_c == 0 && set_2_c == 0) {
        // both are empty set
        status = true;
    } else if ((set_1_c != 0 && set_2_c == 0) || (set_1_c == 0 && set_2_c != 0)) {
        // found some element(s) on either of set
        status = false;
    } else if (set_1_c == set_2_c) {
        // found element(s) on both sets
        for (i = 0; i < attr_index; i++) {
            if (set_1[i] != set_2[i]) {
                status = false;
                break;
            } else {
                status = true;
            }
        }
    }

    return status;
}