#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdbool.h>
#include <errno.h>

extern int errno; // globally holds the error no
int data_size; // holds the data set size read from .cxt file
int attribute_size; // holds the attribute size read from .cxt file
char **dataset_obj; // holds data set objects` names from .cxt file
char **dataset_atr; // holds data set attribute list from .cxt file
int **cross_table; // holds data set cross table from .cxt file
int concept_count = 0; // holds generated concept count

// define concept_t for hold each concept objects and attribute sets
struct concept_t {
    int *objects;
    int *attributes;
};

struct concept_t *concept_latice; // holds main concept latice, generated output

// local functions
void loadData(char *file_path);
void buildInitialConcept(int obj[],int attr[]);
void computeConceptFrom(int *obj,int *attr,int attr_index);
void processConcept(int *obj,int *attr);
bool checkAttribute(int j,int *attr);
void makeExtent(int *extent,int *obj,int attr_index);
void makeIntent(int *intent,int *extent,int attr_index);
bool canonicity(int *attr,int *intent,int attr_index);

int main(){
    char file_path[256]; // hold data source

    // get data source file path as user input
    printf("Enter data source path with name (ex: dataset/tealady.cxt) : ");
    scanf("%s",file_path);
    
    loadData(file_path); // read data from file path

    int ini_obj[data_size]; // initial concept object list
    int ini_attr[attribute_size]; // initial concept attribute list
    buildInitialConcept(ini_obj,ini_attr); // make object and attribute list

    concept_latice = malloc(data_size * sizeof(struct concept_t)); // allocate memory on concept latice

    computeConceptFrom(ini_obj,ini_attr,0); // invoke Close-by-One

    printf("\nTotal Concepts : %d\n\n",concept_count);

    getchar();

    return 0;
}

// load data set file from given location
void loadData(char *file_path) {
    int errnum;
	FILE* file;
	if ((file = fopen(file_path, "rt")) == NULL) {
        errnum = errno;
		fprintf(stderr, "Value of errno: %d\n", errno);
        perror("Error printed by perror");
        fprintf(stderr, "Error opening file: %s\n", strerror( errnum ));
	}
	else {
        printf("\n~~~ Dataset Cross Table ~~~\n\n");

		char buffer[256];
        int line_count = 0;
        int data_read_count = 0;
        int obj_count = 0;
        int atr_count = 0;
		while (fgets(buffer, sizeof(buffer), file)) {
            // process lines
            if(buffer[0] == '\n'){
                // new line found
            } else {
                // skip first character on the .cxt file
                if(line_count != 0){
                    if(line_count == 1){
                        // data size found
                        data_size = atoi(buffer);
                        dataset_obj = (char **)malloc(sizeof(char*) * data_size); // allocate data set object list size
                    } else if(line_count == 2){
                        // attribute size found
                        attribute_size = atoi(buffer);
                        dataset_atr = (char **)malloc(sizeof(char*) * attribute_size); // allocate data set attribute list size
                        // set cross table memory
                        cross_table = malloc(sizeof(int*)*data_size);
                    } else if(line_count > 2 && line_count <= (data_size+2)){
                        // read data set objects
                        dataset_obj[obj_count] = malloc(sizeof(char)*strlen(buffer)); // allocate each char array indexes
                        strcpy(dataset_obj[obj_count++],buffer);
                    } else if(line_count > (2+data_size) && line_count <= (2+data_size+attribute_size)){
                        // read attributes
                        dataset_atr[atr_count] = malloc(sizeof(char)*strlen(buffer)); // allocate each char array indexes
                        strcpy(dataset_atr[atr_count++],buffer);
                        obj_count = 0; // reset obj count
                    } else if(line_count > (2+data_size+attribute_size)){
                        // read cross table
                        cross_table[obj_count] = malloc(sizeof(int)*attribute_size); // allocate cross table row
                        int x;
                        for(x=0;x<attribute_size;x++){
                            // check attribute present or not
                            if(buffer[x] == 'X'){
                                cross_table[obj_count][x] = 1; // assign one when 'X' 
                            } else {
                                cross_table[obj_count][x] = 0; // assign zero when '.'
                            }
                            printf("%d",cross_table[obj_count][x]);
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
void buildInitialConcept(int obj[],int attr[]){
    int i;
    int a;
    /**
     * assign objects
     * pass all objects into list, according to the theorem, (X)
     */
    for(i=0;i<data_size;i++){
        obj[i] = i;
    }

    /**
     * assign attributes
     * set common attribute list for all objects on cross table (X up) 
     */
     // go through attributes
     for(a=0;a<attribute_size;a++){
        bool status = true;
        // go through objects
        for(i=0;i<data_size;i++){
            if(cross_table[i][a] == 0){
                status = false;
                break;
            }
        }
        if(status){
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
void computeConceptFrom(int *obj,int *attr,int attr_index){
    // 1. Process Concept
    processConcept(obj,attr);
    // 2. go through attribute list
    int j;
    for(j=attr_index;j<attribute_size;j++){
        // 3. check current attribute exist or not
        if(!checkAttribute(j,attr)){
            // 4. make extent
            int extent[data_size];
            makeExtent(extent,obj,j);
            // 5. make intent
            int intent[attribute_size];
            makeIntent(intent,extent,j);
            // 6. do canobicity test
            if(canonicity(attr,intent,j)){
                // 7. call computeConceptFrom
                computeConceptFrom(extent,intent,(j+1));
            }
        }
    }
}

// store concept
void processConcept(int *obj,int *attr){
    printf("\n-------------------------------\n");
    printf("Concept - %d\n\n",concept_count);
    int i;
    // set objects details on concept latice
    concept_latice[concept_count].objects = malloc(sizeof(int*)*data_size);
    printf("Object Set : ");
    for(i=0;i<data_size;i++){
        concept_latice[concept_count].objects[i] = obj[i];
        printf("%d ",concept_latice[concept_count].objects[i]);
    }
    printf("\n");
    // set attribute details on concept latice
    concept_latice[concept_count].attributes = malloc(sizeof(int*)*attribute_size);
    printf("Attribute Set : ");
    for(i=0;i<attribute_size;i++){
        concept_latice[concept_count].attributes[i] = attr[i];
        printf("%d ",concept_latice[concept_count].attributes[i]);
    }
    printf("\n-------------------------------\n\n");
    concept_count++;
}

// check attribute contains on attribute list or not
bool checkAttribute(int j,int *attr){
    bool status=true;
    if(attr[j] == 0){
        status = false;
    }
    return status;
}

// make extent
void makeExtent(int *extent,int *obj,int attr_index){
    int i,z;
    printf("extent (attr : %d): ",attr_index);
    // go through cross table
    for(i=0;i<data_size;i++){
        extent[i] = -1;
        if(cross_table[i][attr_index] == 1 && obj[i] != -1){
            extent[i] = i; // set object index to extent list
        }
        printf("%d ",extent[i]);
    }
    printf("\n");
}

// make intent
void makeIntent(int *intent,int *extent,int attr_index){
    int i,a;
    int empty_count=0;
    printf("intent (attr : %d): ",attr_index);
    // check extent is empty set
    for(i=0;i<data_size;i++){
        if(extent[i] != -1){
            empty_count++;
        }
    }
    for(a=0;a<attribute_size;a++){
        // validate on empty extent set
        if(empty_count != data_size){
            bool status = true;
            for(i=0;i<data_size;i++){
                // check extent available
                if(extent[i] != -1){
                    // check related cross table index of current exten attribute availability
                    if(cross_table[i][a] != 1){
                        status = false;
                        break;
                    }
                }
            }
            if(status){
                intent[a] = 1;
            } else {
                intent[a] = 0;
            }
        } else {
            intent[a] = 1;
        }
        printf("%d ",intent[a]);
    }
    printf("\n");
}

// perform canonicity test
bool canonicity(int *attr,int *intent,int attr_index){
    bool status = false;
    bool attr_empty=false;
    bool intent_empty=false;
    int i;
    int emp=0;
    // 1. check empty set for attr
    for(i=0;i<attribute_size;i++){
        if(attr[i] == 0){
            emp++;
        }
    }
    if(emp == attribute_size){
        attr_empty = true;
    }

    // 2. check empty set for intent
    emp=0; // reset
    for(i=0;i<attribute_size;i++){
        if(attr[i] == 0){
            emp++;
        }
    }
    if(emp == attribute_size){
        intent_empty = true;
    }

    if(attr_empty && intent_empty){
        // both sets are empty
        status = true;
    } else {
        for(i=0;i<attr_index;i++){
            if(attr[i] == 1 && intent[i] == 1){
                status = true;
            } 
            else if((attr_empty && intent[i] == 1) || (intent_empty && attr[i] == 1)){
                status = false;
                break;
            }
            else if((attr[i] != 1 && intent[i] == 1) || (attr[i] == 1 && intent[i] != 1)) {
                status = false;
                break;
            }
        }
        if(i == 0){
            status = true;
        }
    }
    return status;
}