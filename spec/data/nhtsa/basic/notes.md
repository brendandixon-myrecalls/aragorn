These JSON files came from the documented NHTSA vPic API (e.g., https://webapi.nhtsa.gov/Default.aspx?Recalls/API/83).

The API *seems* faster than the API used by the NHTSA pages, but the JSON is far more limited in what it returns.
Nor is it "self-documenting" as the JSON returned by the API appears to be.

Here are the mail calls:

* Retrieve all Recalls my make, model, and year: https://webapi.nhtsa.gov/api/Recalls/vehicle/modelyear/2017/make/toyota/model/prius?format=json
* Retrieve campaign details: https://webapi.nhtsa.gov/api/Recalls/vehicle/campaignnumber/16V741000?format=json
