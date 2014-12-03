Stomify Examples
================
The example folder consists of various stomify examples for understanding.

To execute theses examples, coffee-script & 'zappajs' is required.

Execution:
Ex:
```
/usr/local/lib/node_modules/stormify$ coffee examples/simple-controller.coffee
```


1. simple-endpoint.coffee
----------------------------

This example demostrates the simple student DB management and expose REST API operations for DB.
The table will be stored in "/tmp/student.db" location. REST APIs are exposed for DB operations. 

Code overview:

StudentModel :  Defines the Table schema.
StudentDataStore : Defines the DataStore.

### a. POST API
URI: http://localhost:8080/students
Input 
```
{
  "student":
  { 
      "name":"Bob",
      "age": 15,
      "address":"chennai"
  }   
}
```
Output
```
{
    "student": {
        "id": "de20024b-2238-4f23-8258-74699e8e7c30",
        "name": "Bob",
        "age": 15,
        "address": "chennai",
        "accessedOn": "2014-12-03T09:56:28.283Z",
        "modifiedOn": "2014-12-03T09:56:28.283Z",
        "createdOn": "2014-12-03T09:56:28.282Z"
    }
}
```

###b. PUT API
URI:  http://localhost:8080/students/de20024b-2238-4f23-8258-74699e8e7c30

Input:
```
{
  "student":
  { 
      "name":"Bob",
      "age": 20,
      "address":"chennai"
  }   
}

```
Output:
```
{
    "student": {
        "id": "de20024b-2238-4f23-8258-74699e8e7c30",
        "name": "Bob",
        "age": 20,
        "address": "chennai",
        "accessedOn": "2014-12-03T09:56:28.283Z",
        "modifiedOn": "2014-12-03T09:58:09.591Z",
        "createdOn": "2014-12-03T09:56:28.282Z"
    }
}
```

###c. GET API

URI: http://localhost:8080/test/

output :
```
{
    "students": [
        {
            "id": "cfb3004a-0b70-48af-919d-08fce6e5cf33",
            "name": "Suresh",
            "age": 32,
            "address": "chennai",
            "accessedOn": "2014-12-03T07:00:56.668Z",
            "modifiedOn": "2014-12-03T07:00:56.668Z",
            "createdOn": "2014-12-03T07:00:56.667Z"
        },
        {
            "id": "de20024b-2238-4f23-8258-74699e8e7c30",
            "name": "Bob",
            "age": 20,
            "address": "chennai",
            "accessedOn": "2014-12-03T09:56:28.283Z",
            "modifiedOn": "2014-12-03T09:58:09.591Z",
            "createdOn": "2014-12-03T09:56:28.282Z"
        }
    ]
}
```

URI:  http://localhost:8080/students/de20024b-2238-4f23-8258-74699e8e7c30

output :
```
{
    "student": {
        "id": "de20024b-2238-4f23-8258-74699e8e7c30",
        "name": "Bob",
        "age": 20,
        "address": "chennai",
        "accessedOn": "2014-12-03T09:56:28.283Z",
        "modifiedOn": "2014-12-03T09:58:09.591Z",
        "createdOn": "2014-12-03T09:56:28.282Z"
    }
}

```

### d. DELETE API

URI:  http://localhost:8080/students/de20024b-2238-4f23-8258-74699e8e7c30

Output :
```
STATUS 204 No Content
```

2. override-endpoint.coffee
--------
This example demonstrates the overriding default REST API calls with custom operations.
In the StudentDataStore, override flag "serveOverride"  to be set, "serve" function overrides the REST API calls. In this example only POST is overrided. other APIs are not added.

### a. POST API
URI:  http://localhost:8080/students/

Input :
```
{
  "student":
  { 
      "name":"Bob",
      "age": 20,
      "address":"chennai"
  }   
}

```

Output:
```
{
    "student": {
        "name": "Bob",
        "age": 20,
        "address": "chennai"
    }
}
```

3. student-dbms 
-----
This example demostrates the Student DB managemtn with multiple tables (models) and relationships.
Folder: student-dbms






