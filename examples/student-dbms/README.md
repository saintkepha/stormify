stormify-example
==============

Introduction:
-------------

This example, helps to understand  stormify with simple Student Management.

The following Datastore relations  are demonstrated in this execersise.
    'DS.belongsTo'
    'DS.hasMany'
    'DS.computed'

The DB is just designed to use most of stomify functionalities.


DB Schema Details :
-------------------

### Course table: 

Course table consists of the courses offered by the institute.

It consists of id, course name , department.  ID is the key.

### Address Table : 

Address table stores the student addresses. Address Table will be updated during the new student POST.
It consists of id, doorno ,street, place,city,zipcode,phoneno. ID is the key.


### Marks Table:

Marks table stores the student marks. Marks Table will be updated during the new student POST.
It consists of id, subject ,mark. ID is the key.


### Student Table:

Student table is the main table, manages the students.

It consists of id, name, courseid, address, marks.

courseid is a reference key for the Course Table. 
address is a  Address Table Schema (belongsTo relationship)
marks is a array of mark table (hasMany relationship).
result - checks the marks and generates the result (pass/fail)  (computed )


Operations :
----------

### 1. POST /courses

URL: http://localhost:8080/courses

Input :
```
{
  "course" : 
	{
  	"id": "1002",
  	"name":"cloud computing",
  	"department":"CSE"
	}
}
```
Output :
```
{
    "course": {
        "id": "1002",
        "name": "cloud computing",
        "department": "CSE",
        "accessedOn": "2014-12-02T05:26:06.409Z",
        "modifiedOn": "2014-12-02T05:26:06.409Z",
        "createdOn": "2014-12-02T05:26:06.409Z"
    }
}
```
### 2. GET /courses
URL: http://localhost:8080/courses

Output :
```
{
    "courses": [
        {
            "id": "1001",
            "name": "wireless networks",
            "department": "ECE",
            "accessedOn": "2014-12-02T03:49:17.631Z",
            "modifiedOn": "2014-12-02T03:49:17.631Z",
            "createdOn": "2014-12-02T03:49:17.630Z"
        },
        {
            "id": "1002",
            "name": "cloud computing",
            "department": "CSE",
            "accessedOn": "2014-12-02T05:26:06.409Z",
            "modifiedOn": "2014-12-02T05:26:06.409Z",
            "createdOn": "2014-12-02T05:26:06.409Z"
        },
        {
            "id": "1003",
            "name": "network security",
            "department": "CSE",
            "accessedOn": "2014-12-02T03:50:09.570Z",
            "modifiedOn": "2014-12-02T03:50:09.570Z",
            "createdOn": "2014-12-02T03:50:09.570Z"
        }
    ]
}
```
### 3. PUT  /courses/:id

URI: http://localhost:8080/courses/1001

Input:
```
{
  "course" : 
	{
  	"id": "1001",
  	"name":"wireless networks and security",
  	"department":"ECE"
	}
}
```
Output:
```
{
    "course": {
        "id": "1001",
        "name": "wireless networks and security",
        "department": "ECE",
        "accessedOn": "2014-12-02T03:49:17.631Z",
        "modifiedOn": "2014-12-02T05:29:41.355Z",
        "createdOn": "2014-12-02T03:49:17.630Z"
    }
}
```

### 4. DELETE /courses/:id
http://localhost:8080/courses/1003
```
204 No Content
```


### 5. POST /students

In this input data,  "courseid" is a reference course table reference key. 
Address will be saved in the Address table, Marks will be saved to Marks table.

URI: http://localhost:8080/students

Input:
```
{
	"student":
	{
    	"id": "5001",
		"name":"suresh",          
    	"courseid":"1001",
    	"address":
      		{
        		"doorno":"32A",
        		"street":"B.G Road",
        		"place":"bilekelli",
        		"city":"bangalore",
        		"zipcode":560033,
          		"phoneno":9884049883
      		},
      	"marks":[
      		{
      			"subject":"tamil",
      			"mark":90
      		},
        	{
          		"subject":"english",
              	"mark":60
        	}
        		] 
	}  
}
```
Output:
```
{
    "student": {
        "id": "5001",
        "name": "suresh",
        "address": {
            "doorno": "32A",
            "street": "B.G Road",
            "place": "bilekelli",
            "city": "bangalore",
            "zipcode": 560033,
            "phoneno": 9884049883,
            "id": "0dc22c58-f887-4b9c-86d9-b7455a470ec8"
        },
        "courseid": "1001",
        "marks": [
            {
                "subject": "tamil",
                "mark": 90,
                "id": "27b4c50c-c8df-48cf-998a-b3f9e48a073e"
            },
            {
                "subject": "english",
                "mark": 60,
                "id": "9fe84219-de86-41c9-aaaf-a1f5d1fdcb26"
            }
        ],
        "result": "pass",
        "accessedOn": "2014-12-02T05:43:11.504Z",
        "modifiedOn": "2014-12-02T05:43:11.504Z",
        "createdOn": "2014-12-02T05:43:11.504Z"
    }
}
```
Note:  Marks table will be updated with the marks data and address table will be updated with the address data.

### 6. DELETE /students/:id
URI: http://localhost:8080/students/5001

deletes the student from the student table, address from the address table and marks from the mark table.

### 7. GET /students
### 7. GET /students/:id







