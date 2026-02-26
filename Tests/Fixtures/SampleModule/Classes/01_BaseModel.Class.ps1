class BaseModel {
    [string]$Id
    [datetime]$CreatedAt

    BaseModel() {
        $this.Id = [guid]::NewGuid().ToString()
        $this.CreatedAt = Get-Date
    }
}
