This data came via the (undocumented?) NHTSA API rooted at https://api.nhtsa.gov/.

This API *seems* to back the NHTSA pages and some calls *seem* to require an authN/Z token of some sort (e.g.,
the VIN status API call showing how many recalls remain unaddressed for the specified VIN).

Each JSON is self-describing, containing the link used to retrieve it.

Some calls accept filters (e.g., data=recalls) that limit the returned data. Expressing no filters returns a lot of data.
