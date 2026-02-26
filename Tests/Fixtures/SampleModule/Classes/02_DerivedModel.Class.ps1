class DerivedModel : BaseModel {
    [string]$Name
    [string]$Description

    DerivedModel([string]$Name) : base() {
        $this.Name = $Name
    }
}
